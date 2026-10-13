import Foundation
import Accelerate
import NullPlayerCore

// The visualization tap: upstream AudioEngine's analysis (75-band spectrum, PCM for the
// oscilloscope, stereo and full-rate PCM, FFT magnitudes, vis_classic's 576-sample waveform),
// fed from PipeWireCapture instead of an AVAudioEngine mixer tap. The members below the
// marker are upstream's, nearly verbatim; changes: no BPM detector yet (needs aubio), and
// notifications/delegate calls go through `engine`.
final class VisualizationTap {
    weak var engine: AudioEngine?

    init() {
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD)
        loadNormalizationMode()
        NotificationCenter.default.addObserver(forName: NSNotification.Name("SpectrumSettingsChanged"),
                                               object: nil, queue: .main) { [weak self] _ in
            self?.loadNormalizationMode()
        }
    }

    private func loadNormalizationMode() {
        if let saved = UserDefaults.standard.string(forKey: "spectrumNormalizationMode"),
           let mode = SpectrumNormalizationMode(rawValue: saved) {
            spectrumNormalizationMode = mode
        }
    }

    var anyConsumer: Bool { spectrumNeeded || waveformNeeded || stereoNeeded || fullStereoNeeded || magnitudesNeeded }

    /// One captured block, shaped like the AVAudioPCMBuffer upstream's tap hands over.
    struct Block {
        struct Format { let sampleRate: Double; let channelCount: UInt32 }
        let floatChannelData: UnsafePointer<UnsafeMutablePointer<Float>>?
        let frameLength: UInt32
        let format: Format
    }

    /// Called on the capture thread for every block.
    func process(channels: UnsafePointer<UnsafeMutablePointer<Float>>, frames: Int, sampleRate: Double) {
        processAudioBuffer(Block(floatChannelData: channels, frameLength: UInt32(frames),
                                 format: .init(sampleRate: sampleRate, channelCount: 2)))
    }

    /// Playback stopped: bars fall to zero, as upstream's stop does.
    func clear() {
        spectrumData = Array(repeating: 0, count: spectrumData.count)
        engine?.delegate?.audioEngineDidUpdateSpectrum(spectrumData)
        NotificationCenter.default.post(name: .audioSpectrumDataUpdated, object: engine,
                                        userInfo: ["spectrum": spectrumData])
    }

    // MARK: - Upstream (Audio/AudioEngine.swift)

    /// Spectrum analyzer data (75 bands for classic skin-style visualization)
    private(set) var spectrumData: [Float] = Array(repeating: 0, count: 75)
    
    /// Running peak averages for adaptive spectrum normalization (per frequency region)
    /// Index 0 = bass (bands 0-24), 1 = mid (bands 25-49), 2 = treble (bands 50-74)
    private var spectrumRegionPeaks: [Float] = [0.0, 0.0, 0.0]
    
    /// Smoothed reference levels for each region (prevents pulsing from max() jumps)
    private var spectrumRegionReferenceLevels: [Float] = [0.0, 0.0, 0.0]
    
    /// Global adaptive peak for adaptive normalization mode
    private var spectrumGlobalPeak: Float = 0.0
    
    /// Smoothed global reference level (prevents pulsing from max() jumps)
    private var spectrumGlobalReferenceLevel: Float = 0.0
    
    /// Current spectrum normalization mode (cached from UserDefaults, updated via notification)
    private var spectrumNormalizationMode: SpectrumNormalizationMode = .accurate
    
    /// Real-time BPM detector for tempo display
    
    
    /// Raw PCM audio data for waveform visualization (mono, normalized -1 to 1)
    private(set) var pcmData: [Float] = Array(repeating: 0, count: 512)
    
    /// PCM sample rate for visualization timing
    private(set) var pcmSampleRate: Double = 44100
    
    /// Reusable userInfo dict for PCM notifications (avoids per-callback allocation)
    private var pcmUserInfo: [String: Any] = [:]

    /// Reusable 576-sample stereo waveform buffers for vis_classic exact mode
    private var waveformLeftU8 = [UInt8](repeating: 128, count: 576)
    private var waveformRightU8 = [UInt8](repeating: 128, count: 576)
    private var waveformUserInfo: [String: Any] = [:]
    private var waveformLeftRing = [Float](repeating: 0, count: 8192)
    private var waveformRightRing = [Float](repeating: 0, count: 8192)
    private var waveformRingReadIndex = 0
    private var waveformRingWriteIndex = 0
    private var waveformRingCount = 0

    /// FFT setup for spectrum analysis
    private var fftSetup: vDSP_DFT_Setup?
    private let fftSize: Int = 2048  // Match streaming FFT for consistent display
    
    // MARK: - Spectrum Update Throttling (Memory Optimization)
    
    /// Last time spectrum notification was posted (throttle to 60Hz max)
    private var lastSpectrumUpdateTime: CFAbsoluteTime = 0
    private let spectrumUpdateInterval: CFAbsoluteTime = 1.0 / 60.0  // 60Hz max
    
    /// Flag to coalesce main queue PCM dispatches
    private var pendingPcmUpdate = false

    /// Latest spectrum frame waiting for the main queue. Protected because FFT runs
    /// off-main while UI consumers read on main.
    private let spectrumUpdateLock = NSLock()
    private var pendingSpectrumFrame: [Float]?
    private var spectrumUpdateScheduled = false
    
    // MARK: - Spectrum Consumer Tracking

    /// Consumer registrations are **ref-counted** (id → live count), not a plain set.
    /// This makes registration order-independent during a live UI teardown/rebuild: if an
    /// old view (e.g. `"spectrumView"`) deinitializes — and removes its registration —
    /// *after* its replacement has already registered the same id, the count merely drops
    /// from 2→1 and the producer stays alive. A plain `Set` would have the late `remove`
    /// wipe the new view's registration. See `WindowManager.teardownModeDependentWindows()`.

    /// Spectrum consumers — FFT is skipped entirely when this is empty
    private var spectrumConsumers: [String: Int] = [:]

    /// Live waveform consumers — 576-sample waveform chunk generation is skipped entirely when this is empty.
    private var waveformConsumers: [String: Int] = [:]

    /// Stereo PCM consumers — stereo tap is skipped entirely when this is empty
    private var stereoConsumers: [String: Int] = [:]

    /// Full-rate stereo PCM consumers — full-rate stereo tap is skipped entirely when this is empty
    private var fullStereoConsumers: [String: Int] = [:]

    /// Magnitudes consumers — raw FFT magnitude posting is skipped entirely when this is empty
    private var magnitudesConsumers: [String: Int] = [:]

    /// Decrement a ref-counted consumer id, removing the key when it reaches zero.
    private func releaseConsumer(_ id: String, from consumers: inout [String: Int]) {
        guard let count = consumers[id] else { return }
        if count <= 1 {
            consumers[id] = nil
        } else {
            consumers[id] = count - 1
        }
    }

    func addSpectrumConsumer(_ id: String) {
        spectrumConsumers[id, default: 0] += 1
    }

    func removeSpectrumConsumer(_ id: String) {
        releaseConsumer(id, from: &spectrumConsumers)
    }

    var spectrumNeeded: Bool { !spectrumConsumers.isEmpty }

    func addWaveformConsumer(_ id: String) {
        waveformConsumers[id, default: 0] += 1
    }

    func removeWaveformConsumer(_ id: String) {
        releaseConsumer(id, from: &waveformConsumers)
    }

    var waveformNeeded: Bool { !waveformConsumers.isEmpty }

    func addStereoConsumer(_ id: String) {
        stereoConsumers[id, default: 0] += 1
    }

    func removeStereoConsumer(_ id: String) {
        releaseConsumer(id, from: &stereoConsumers)
    }

    var stereoNeeded: Bool { !stereoConsumers.isEmpty }

    func addFullStereoConsumer(_ id: String) {
        fullStereoConsumers[id, default: 0] += 1
    }

    func removeFullStereoConsumer(_ id: String) {
        releaseConsumer(id, from: &fullStereoConsumers)
    }

    var fullStereoNeeded: Bool { !fullStereoConsumers.isEmpty }

    func addMagnitudesConsumer(_ id: String) {
        magnitudesConsumers[id, default: 0] += 1
    }

    func removeMagnitudesConsumer(_ id: String) {
        releaseConsumer(id, from: &magnitudesConsumers)
    }

    var magnitudesNeeded: Bool { !magnitudesConsumers.isEmpty }
    // MARK: - Pre-allocated FFT Buffers (Memory Optimization)

    /// Pre-allocated buffers to avoid per-callback allocations
    private var fftSamples = [Float](repeating: 0, count: 2048)
    private var fftWindow = [Float](repeating: 0, count: 2048)
    private var fftRealIn = [Float](repeating: 0, count: 2048)
    private var fftImagIn = [Float](repeating: 0, count: 2048)
    private var fftRealOut = [Float](repeating: 0, count: 2048)
    private var fftImagOut = [Float](repeating: 0, count: 2048)
    private var fftMagnitudes = [Float](repeating: 0, count: 1024)
    private var fftLogMagnitudes = [Float](repeating: 0, count: 1024)
    private var fftNewSpectrum = [Float](repeating: 0, count: 75)
    private var fftPcmSamples = [Float](repeating: 0, count: 512)
    /// Pre-allocated stereo PCM buffers (512 samples each for left and right channels)
    private var stereoPcmLeft = [Float](repeating: 0, count: 512)
    private var stereoPcmRight = [Float](repeating: 0, count: 512)
    /// Pre-allocated full-rate stereo PCM buffers (2048 samples each for left and right channels)
    private var fullStereoPcmLeft = [Float](repeating: 0, count: 2048)
    private var fullStereoPcmRight = [Float](repeating: 0, count: 2048)

    /// Pre-computed frequency weights for spectrum analyzer (light compensation)
    private let spectrumFrequencyWeights: [Float] = {
        // Generate weights for 75 bands spanning 20Hz-20kHz logarithmically
        // Keep this shared producer conservative; visualizers apply their own shaping.
        let bandCount = 75
        let minFreq: Float = 20
        let maxFreq: Float = 20000
        
        return (0..<bandCount).map { band in
            let freqRatio = Float(band) / Float(bandCount - 1)
            let freq = minFreq * pow(maxFreq / minFreq, freqRatio)

            if freq < 40 {
                return 0.70
            } else if freq < 100 {
                return 0.85
            } else if freq < 300 {
                return 0.92
            } else {
                return 1.0
            }
        }
    }()
    
    /// Pre-computed bandwidth scale factors for flat pink noise display
    /// Pink noise has magnitude ∝ 1/sqrt(f), bandwidth ∝ f for log bands
    /// Scaling by sqrt(bandwidth) gives: 1/sqrt(f) × sqrt(f) = constant (flat)
    private let spectrumBandwidthScales: [Float] = {
        let bandCount = 75
        let minFreq: Float = 20
        let maxFreq: Float = 20000
        let ratio = pow(maxFreq / minFreq, 1.0 / Float(bandCount))
        
        // Reference bandwidth at 1000 Hz for normalization
        let refBandwidth = 1000.0 * (ratio - 1.0)
        
        return (0..<bandCount).map { band in
            let startFreq = minFreq * pow(maxFreq / minFreq, Float(band) / Float(bandCount))
            let endFreq = minFreq * pow(maxFreq / minFreq, Float(band + 1) / Float(bandCount))
            let bandwidth = endFreq - startFreq
            return sqrt(bandwidth / refBandwidth)
        }
    }()

    private func processAudioBuffer(_ buffer: Block) {
        guard spectrumNeeded || waveformNeeded || stereoNeeded || fullStereoNeeded || magnitudesNeeded else { return }
        guard let channelData = buffer.floatChannelData else { return }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        let channelCount = Int(buffer.format.channelCount)
        let bufferSampleRate = buffer.format.sampleRate

        if waveformNeeded {
            enqueueWaveformSamplesAndPost(
                channelData: channelData,
                channelCount: channelCount,
                frameCount: frameCount,
                sampleRate: bufferSampleRate
            )
        }

        // Publish stereo PCM data when needed (independent of spectrum)
        if stereoNeeded && frameCount >= 512 {
            let pcmSize = 512
            let pcmStride = frameCount / pcmSize
            // Extract and downsample left and right channels
            if channelCount == 1 {
                // Mono: duplicate to both channels
                for i in 0..<pcmSize {
                    let sample = channelData[0][i * pcmStride]
                    stereoPcmLeft[i] = sample
                    stereoPcmRight[i] = sample
                }
            } else {
                // Stereo: separate channels
                for i in 0..<pcmSize {
                    stereoPcmLeft[i] = channelData[0][i * pcmStride]
                    stereoPcmRight[i] = channelData[1][i * pcmStride]
                }
            }

            // Post notification with left/right copies
            let leftCopy = Array(stereoPcmLeft)
            let rightCopy = Array(stereoPcmRight)
            NotificationCenter.default.post(
                name: .audioStereoPCMDataUpdated,
                object: engine,
                userInfo: [
                    "left": leftCopy,
                    "right": rightCopy,
                    "sampleRate": bufferSampleRate
                ]
            )
        }

        // Publish full-rate (undecimated) stereo PCM data when needed
        if fullStereoNeeded && frameCount >= 2048 {
            // Extract exactly 2048 samples from the buffer
            let pcmSize = 2048
            if channelCount == 1 {
                // Mono: duplicate to both channels
                for i in 0..<pcmSize {
                    let sample = channelData[0][i]
                    fullStereoPcmLeft[i] = sample
                    fullStereoPcmRight[i] = sample
                }
            } else {
                // Stereo: separate channels
                for i in 0..<pcmSize {
                    fullStereoPcmLeft[i] = channelData[0][i]
                    fullStereoPcmRight[i] = channelData[1][i]
                }
            }

            // Post notification with left/right copies
            let leftCopy = Array(fullStereoPcmLeft)
            let rightCopy = Array(fullStereoPcmRight)
            NotificationCenter.default.post(
                name: .audioStereoPCMFullDataUpdated,
                object: engine,
                userInfo: [
                    "left": leftCopy,
                    "right": rightCopy,
                    "sampleRate": bufferSampleRate
                ]
            )
        }

        // The FFT runs when spectrum OR raw magnitudes are demanded; the 75-band spectrum
        // work below is gated separately by `spectrumNeeded` so an octave-only (magnitudes)
        // consumer does not pay for it.
        guard spectrumNeeded || magnitudesNeeded, frameCount >= fftSize, let fftSetup = fftSetup else { return }

        // Throttle updates to 60Hz max to prevent memory buildup
        let now = CFAbsoluteTimeGetCurrent()
        let shouldUpdate = now - lastSpectrumUpdateTime >= spectrumUpdateInterval
        guard shouldUpdate else { return }
        lastSpectrumUpdateTime = now

        // Get audio samples (mono mix if stereo) - use pre-allocated buffer
        if channelCount == 1 {
            memcpy(&fftSamples, channelData[0], fftSize * MemoryLayout<Float>.size)
        } else {
            // Mix stereo to mono
            for i in 0..<fftSize {
                fftSamples[i] = (channelData[0][i] + channelData[1][i]) / 2.0
            }
        }

        // Store raw PCM data for waveform visualization (before windowing)
        // Downsample to 512 samples for efficient storage and lowest latency
        let pcmSize = 512
        let pcmStride = fftSize / pcmSize
        for i in 0..<pcmSize {
            fftPcmSamples[i] = fftSamples[i * pcmStride]
        }

        // Post notification for low-latency visualization (direct from audio tap)
        // Copy to avoid data races since we reuse the buffer
        let pcmCopy = Array(fftPcmSamples)
        pcmUserInfo["pcm"] = pcmCopy
        pcmUserInfo["sampleRate"] = bufferSampleRate
        NotificationCenter.default.post(
            name: .audioPCMDataUpdated,
            object: engine,
            userInfo: pcmUserInfo
        )

        // Also store in property for legacy access - coalesce dispatches
        if !pendingPcmUpdate {
            pendingPcmUpdate = true
            let pcmForMain = pcmCopy
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.pendingPcmUpdate = false
                self.pcmSampleRate = bufferSampleRate
                self.pcmData = pcmForMain
            }
        }

        // Apply Hann window - use pre-allocated buffers
        vDSP_hann_window(&fftWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(fftSamples, 1, fftWindow, 1, &fftSamples, 1, vDSP_Length(fftSize))
        
        // Perform FFT - use pre-allocated buffers
        // Zero out imagIn (realIn gets samples)
        memset(&fftImagIn, 0, fftSize * MemoryLayout<Float>.size)
        memcpy(&fftRealIn, &fftSamples, fftSize * MemoryLayout<Float>.size)
        
        vDSP_DFT_Execute(fftSetup, &fftRealIn, &fftImagIn, &fftRealOut, &fftImagOut)
        
        // Calculate magnitudes - use pre-allocated buffer
        for i in 0..<fftSize / 2 {
            fftMagnitudes[i] = sqrt(fftRealOut[i] * fftRealOut[i] + fftImagOut[i] * fftImagOut[i])
        }

        // Post raw linear magnitudes for octave band analysis (gated by magnitudesNeeded)
        if magnitudesNeeded {
            let magnitudesCopy = Array(fftMagnitudes.prefix(fftSize / 2))
            NotificationCenter.default.post(
                name: .audioFFTMagnitudesUpdated,
                object: engine,
                userInfo: [
                    "magnitudes": magnitudesCopy,
                    "sampleRate": buffer.format.sampleRate,
                    "fftSize": fftSize
                ]
            )
        }

        // Everything below is the 75-band spectrum path; skip it for magnitudes-only consumers.
        guard spectrumNeeded else { return }

        // Convert to dB and normalize - use pre-allocated buffer
        var one: Float = 1.0
        vDSP_vdbcon(fftMagnitudes, 1, &one, &fftLogMagnitudes, 1, vDSP_Length(fftSize / 2), 0)
        
        // Map to 75 bands (classic skin-style) using logarithmic frequency mapping
        // Zero out pre-allocated buffer
        let bandCount = 75
        memset(&fftNewSpectrum, 0, bandCount * MemoryLayout<Float>.size)
        
        let minFreq: Float = 20
        let maxFreq: Float = 20000
        let sampleRate = Float(buffer.format.sampleRate)
        let binWidth = sampleRate / Float(fftSize)
        let normMode = spectrumNormalizationMode
        
        for band in 0..<bandCount {
            // Calculate band edges and center frequency
            let startFreq = minFreq * pow(maxFreq / minFreq, Float(band) / Float(bandCount))
            let endFreq = minFreq * pow(maxFreq / minFreq, Float(band + 1) / Float(bandCount))
            let centerFreq = sqrt(startFreq * endFreq)
            
            if normMode == .accurate {
                // Accurate mode - sum total power across all bins in band, then convert to dB
                // High freq bands have more bins, so total power scales with bandwidth
                let startBin = max(1, Int(startFreq / binWidth))
                let endBin = max(startBin, min(fftSize / 2 - 1, Int(endFreq / binWidth)))
                
                // Peak aggregation per band (BeSpec approach).
                // RMS averaging dilutes treble: a high-freq band with 80 mostly-empty bins
                // averages to near zero. Peak picks the loudest component, giving treble
                // equal standing with bass.
                var peakMag: Float = 0
                for bin in startBin...endBin {
                    if fftMagnitudes[bin] > peakMag { peakMag = fftMagnitudes[bin] }
                }

                // BeSpec calibration: HANN_CORRECTION (2.0) × energy-preserving FFT scale (1/√N).
                let bespecFactor: Float = 2.0 / sqrt(Float(fftSize))
                let calibratedMag = peakMag * bespecFactor
                let dB = 20.0 * log10(max(calibratedMag, 1e-10))

                let ceiling: Float = 0.0
                let floor: Float = -20.0
                let normalized = (dB - floor) / (ceiling - floor)
                
                fftNewSpectrum[band] = max(0, min(1.0, normalized))
            } else {
                // Adaptive/Dynamic modes - interpolate at center frequency
                let exactBin = centerFreq / binWidth
                let lowerBin = max(0, Int(exactBin))
                let upperBin = min(lowerBin + 1, fftSize / 2 - 1)
                let fraction = exactBin - Float(lowerBin)
                let interpMag = fftMagnitudes[lowerBin] * (1.0 - fraction) + fftMagnitudes[upperBin] * fraction
                
                // Apply bandwidth scaling and frequency weighting
                let bandMagnitude = interpMag * spectrumBandwidthScales[band]
                fftNewSpectrum[band] = bandMagnitude * spectrumFrequencyWeights[band]
            }
        }
        
        // Apply normalization based on selected mode
        switch normMode {
        case .accurate:
            // dB scaling already applied above - no additional processing needed
            break
            
        case .adaptive:
            // Global adaptive normalization - adapts to overall loudness
            // Preserves relative levels between frequency regions
            var globalPeak: Float = 0
            for i in 0..<bandCount {
                globalPeak = max(globalPeak, fftNewSpectrum[i])
            }
            
            if globalPeak > 0 {
                // Update global adaptive peak (slow rise, slower decay)
                if globalPeak > spectrumGlobalPeak {
                    spectrumGlobalPeak = spectrumGlobalPeak * 0.92 + globalPeak * 0.08
                } else {
                    spectrumGlobalPeak = spectrumGlobalPeak * 0.995 + globalPeak * 0.005
                }
                
                // Target reference level based on adaptive peak
                let targetReferenceLevel = max(spectrumGlobalPeak * 0.5, globalPeak * 0.3)
                
                // Smooth the reference level to prevent pulsing from max() jumps
                spectrumGlobalReferenceLevel = spectrumGlobalReferenceLevel * 0.85 + targetReferenceLevel * 0.15
                let referenceLevel = max(spectrumGlobalReferenceLevel, 0.001)
                
                // Normalize all bands using global reference
                for i in 0..<bandCount {
                    let normalized = min(1.0, fftNewSpectrum[i] / referenceLevel)
                    fftNewSpectrum[i] = pow(normalized, 0.5)  // Square root curve for dynamics
                }
            }
            
        case .dynamic:
            // Per-region normalization - best visual appeal for music
            // Each frequency region (bass, mid, treble) normalizes independently
            let regionRanges = [(0, 25), (25, 50), (50, 75)]  // bass, mid, treble
            
            for (regionIndex, (start, end)) in regionRanges.enumerated() {
                // Find peak in this region
                var regionPeak: Float = 0.0
                for i in start..<end {
                    regionPeak = max(regionPeak, fftNewSpectrum[i])
                }
                
                guard regionPeak > 0 else { continue }
                
                // Update adaptive peak for this region
                if regionPeak > spectrumRegionPeaks[regionIndex] {
                    spectrumRegionPeaks[regionIndex] = spectrumRegionPeaks[regionIndex] * 0.92 + regionPeak * 0.08
                } else {
                    spectrumRegionPeaks[regionIndex] = spectrumRegionPeaks[regionIndex] * 0.995 + regionPeak * 0.005
                }
                
                // Target reference level for this region
                let targetReferenceLevel = max(spectrumRegionPeaks[regionIndex] * 0.5, regionPeak * 0.3)
                
                // Smooth the reference level to prevent pulsing from max() jumps
                spectrumRegionReferenceLevels[regionIndex] = spectrumRegionReferenceLevels[regionIndex] * 0.85 + targetReferenceLevel * 0.15
                let referenceLevel = max(spectrumRegionReferenceLevels[regionIndex], 0.001)
                
                // Normalize bands in this region
                for i in start..<end {
                    let normalized = min(1.0, fftNewSpectrum[i] / referenceLevel)
                    fftNewSpectrum[i] = pow(normalized, 0.5)  // Square root curve
                }
            }
        }
        
        // Smooth with previous values (decay) and update on main thread.
        // Keep only the latest frame while one main-queue update is pending.
        let spectrumCopy = Array(fftNewSpectrum)
        var shouldScheduleSpectrumUpdate = false
        spectrumUpdateLock.lock()
        pendingSpectrumFrame = spectrumCopy
        if !spectrumUpdateScheduled {
            spectrumUpdateScheduled = true
            shouldScheduleSpectrumUpdate = true
        }
        spectrumUpdateLock.unlock()

        if shouldScheduleSpectrumUpdate {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.spectrumUpdateLock.lock()
                let spectrumFrame = self.pendingSpectrumFrame
                self.pendingSpectrumFrame = nil
                self.spectrumUpdateScheduled = false
                self.spectrumUpdateLock.unlock()

                guard let spectrumFrame else { return }
                for i in 0..<bandCount {
                    // Fast attack, smooth decay for all modes
                    if spectrumFrame[i] > self.spectrumData[i] {
                        self.spectrumData[i] = spectrumFrame[i]
                    } else {
                        self.spectrumData[i] = self.spectrumData[i] * 0.90 + spectrumFrame[i] * 0.10
                    }
                }
                self.engine?.delegate?.audioEngineDidUpdateSpectrum(self.spectrumData)
                NotificationCenter.default.post(
                    name: .audioSpectrumDataUpdated,
                    object: engine,
                    userInfo: ["spectrum": self.spectrumData]
                )
            }
        }
    }

    private func enqueueWaveformSamplesAndPost(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        frameCount: Int,
        sampleRate: Double
    ) {
        guard channelCount > 0 else { return }
        for i in 0..<frameCount {
            let left = channelData[0][i]
            let right = channelCount > 1 ? channelData[1][i] : left
            appendWaveformSample(left: left, right: right)
        }
        postAvailableWaveformChunks(sampleRate: sampleRate)
    }

    private func appendWaveformSample(left: Float, right: Float) {
        if waveformRingCount == waveformLeftRing.count {
            waveformRingReadIndex = (waveformRingReadIndex + 1) % waveformLeftRing.count
            waveformRingCount -= 1
        }

        waveformLeftRing[waveformRingWriteIndex] = left
        waveformRightRing[waveformRingWriteIndex] = right
        waveformRingWriteIndex = (waveformRingWriteIndex + 1) % waveformLeftRing.count
        waveformRingCount += 1
    }

    private func postAvailableWaveformChunks(sampleRate: Double) {
        let chunkSize = waveformLeftU8.count
        while waveformRingCount >= chunkSize {
            var index = waveformRingReadIndex
            for i in 0..<chunkSize {
                let leftInt = Int((waveformLeftRing[index] * 127.0) + 128.0)
                let rightInt = Int((waveformRightRing[index] * 127.0) + 128.0)
                waveformLeftU8[i] = UInt8(clamping: leftInt)
                waveformRightU8[i] = UInt8(clamping: rightInt)
                index += 1
                if index == waveformLeftRing.count {
                    index = 0
                }
            }

            waveformRingReadIndex = index
            waveformRingCount -= chunkSize

            waveformUserInfo["left"] = waveformLeftU8
            waveformUserInfo["right"] = waveformRightU8
            waveformUserInfo["sampleRate"] = sampleRate
            NotificationCenter.default.post(
                name: .audioWaveform576DataUpdated,
                object: engine,
                userInfo: waveformUserInfo
            )
        }
    }
    
}
