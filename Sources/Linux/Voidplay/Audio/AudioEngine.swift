import Foundation
import CoreAudio
import NullPlayerCore

// The Linux AudioEngine: upstream's public surface (state, queue, shuffle/repeat, EQ, tuning,
// scrobbling and play-history hooks) over libmpv instead of AVAudioEngine. mpv owns decoding,
// network streams, resampling and output; gapless comes from queueing the next track in mpv.
//
// ponytail: no Sweet Fades crossfade, spectrum/PCM taps, normalization or casting yet — the
// GUI and casting stages add them. Listeners still get every notification upstream posts.

// MARK: - Shared types (mirrors Audio/AudioEngine.swift)

extension Notification.Name {
    static let audioPCMDataUpdated = Notification.Name("audioPCMDataUpdated")
    static let audioStereoPCMDataUpdated = Notification.Name("audioStereoPCMDataUpdated")
    static let audioStereoPCMFullDataUpdated = Notification.Name("audioStereoPCMFullDataUpdated")
    static let audioSpectrumDataUpdated = Notification.Name("audioSpectrumDataUpdated")
    static let audioFFTMagnitudesUpdated = Notification.Name("audioFFTMagnitudesUpdated")
    static let audioPlaybackStateChanged = Notification.Name("audioPlaybackStateChanged")
    static let audioPlaybackOptionsChanged = Notification.Name("audioPlaybackOptionsChanged")
    static let audioTrackDidChange = Notification.Name("audioTrackDidChange")
    static let audioTrackDidFailToLoad = Notification.Name("audioTrackDidFailToLoad")
    static let bpmUpdated = Notification.Name("bpmUpdated")
    static let audioTrackDidFinishNaturally = Notification.Name("audioTrackDidFinishNaturally")
    static let audioQueueDidExhaust = Notification.Name("audioQueueDidExhaust")
}

enum PlaybackState {
    case stopped
    case playing
    case paused
}

protocol AudioEngineDelegate: AnyObject {
    func audioEngineDidChangeState(_ state: PlaybackState)
    func audioEngineDidUpdateTime(current: TimeInterval, duration: TimeInterval)
    func audioEngineDidChangeTrack(_ track: Track?)
    func audioEngineDidUpdateSpectrum(_ levels: [Float])
    func audioEngineDidChangePlaylist()
    func audioEngineDidFailToLoadTrack(_ track: Track, error: Error)
    func audioEngineDidEncounterPlaybackError()
    func audioEngineUserPlayRequestDidFail(_ track: Track, error: Error, fileIsMissing: Bool)
}

extension AudioEngineDelegate {
    func audioEngineDidEncounterPlaybackError() {}
    func audioEngineUserPlayRequestDidFail(_ track: Track, error: Error, fileIsMissing: Bool) {}
}

// MARK: - Engine

class AudioEngine {
    static var isHeadless = false

    weak var delegate: AudioEngineDelegate?

    private(set) var state: PlaybackState = .stopped {
        didSet {
            guard state != oldValue else { return }
            delegate?.audioEngineDidChangeState(state)
            NotificationCenter.default.post(name: .audioPlaybackStateChanged, object: self, userInfo: ["state": state])
        }
    }

    private(set) var currentTrack: Track? {
        didSet {
            delegate?.audioEngineDidChangeTrack(currentTrack)
            NotificationCenter.default.post(name: .audioTrackDidChange, object: self,
                                            userInfo: currentTrack.map { ["track": $0] })
        }
    }

    private(set) var playlist: [Track] = []
    private(set) var currentIndex = -1

    var volume: Float = 0.2 {
        didSet { mpv.set("volume", Double(max(0, min(1, volume))) * 100) }
    }

    var shuffleEnabled = false {
        didSet {
            if shuffleEnabled { shuffle.rebuild(count: playlist.count, anchoredAt: currentIndex) } else { shuffle.clear() }
            replaceQueuedNext()
            notifyPlaybackOptionsChanged()
        }
    }

    var repeatEnabled = false {
        didSet {
            replaceQueuedNext()
            notifyPlaybackOptionsChanged()
        }
    }

    /// Position within the current track; for a cue track, from its start mark.
    private(set) var currentTime: TimeInterval = 0

    var duration: TimeInterval {
        guard let track = currentTrack else { return 0 }
        if let start = track.cueStartOffset {
            if let end = track.cueEndOffset { return end - start }
            return max(0, (mpvDuration ?? 0) - start)
        }
        // A live stream's mpv "duration" is just what has buffered so far.
        if track.isRadioOrigin || RadioManager.shared.isActive { return track.duration ?? 0 }
        return mpvDuration ?? track.duration ?? 0
    }

    private let mpv: MpvPlayer
    private var shuffle = ShuffleOrder()
    /// Playlist index mpv holds after the current file, for a gapless hand-over. Nil = none queued.
    private var queuedNextIndex: Int?
    private var pendingRequeue = false
    private var mpvDuration: TimeInterval?
    private var lastTimeReport = Date.distantPast

    let tuningController = PitchTuningController()
    private var eqEnabled = false
    private var preampGain: Float = 0
    private var eqGains = [Float](repeating: 0, count: EQConfiguration.classic10.bandCount)
    private(set) var activeEQConfiguration = EQConfiguration.classic10

    /// `mpvOptions` overrides the defaults; tests pass a silent, untimed output.
    init(mpvOptions: [String: String] = [:]) {
        guard let mpv = MpvPlayer(options: [
            "vid": "no",
            "audio-display": "no",
            "terminal": "no",
            "msg-level": "all=no",
            "idle": "yes",
            "gapless-audio": "weak",
            "prefetch-playlist": "yes",
            "audio-client-name": "voidplay",
            "volume-max": "100",
            "ytdl": "no",
            "input-default-bindings": "no",
            "audio-pitch-correction": "yes",
        ].merging(mpvOptions) { $1 }) else {
            fatalError("libmpv failed to initialise")
        }
        self.mpv = mpv
        mpv.onEvent = { [weak self] in self?.handle($0) }
        mpv.set("volume", Double(volume) * 100)
        tuningController.loadFromDefaults()
        applyAudioFilters()
    }

    // MARK: Queue

    func loadFiles(_ urls: [URL]) {
        let validation = AudioFileValidator.quickValidate(urls: urls, includeVideo: true)
        loadTracks(validation.validURLs.compactMap { Track(lightweightURL: $0) })
    }

    func loadTracks(_ tracks: [Track]) {
        let valid = tracks.filter { $0.url.scheme == "http" || $0.url.scheme == "https"
            || FileManager.default.fileExists(atPath: $0.url.path) }
        if valid.count < tracks.count {
            NSLog("loadTracks: %d missing file(s) skipped", tracks.count - valid.count)
        }
        stopRadioIfLoadingNonRadioContent(incomingTrackURL: valid.first?.url)
        stop()
        playlist = valid
        shuffle.clear()
        if !valid.isEmpty {
            currentIndex = shuffleEnabled ? (shuffle.startCycle(count: valid.count) ?? 0) : 0
            currentTrack = playlist[currentIndex]
        }
        delegate?.audioEngineDidChangePlaylist()
    }

    func appendTracks(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        playlist += tracks
        playlistDidMutate()
    }

    func insertTracksAfterCurrent(_ tracks: [Track], startPlaybackIfEmpty: Bool = true) {
        guard !tracks.isEmpty else { return }
        let wasEmpty = playlist.isEmpty
        let at = currentIndex < 0 ? 0 : min(currentIndex + 1, playlist.count)
        playlist.insert(contentsOf: tracks, at: at)
        playlistDidMutate()
        if wasEmpty && startPlaybackIfEmpty { playTrack(at: 0) }
    }

    func playNow(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        if playlist.isEmpty {
            loadTracks(tracks)
            play()
        } else {
            let at = currentIndex < 0 ? 0 : min(currentIndex + 1, playlist.count)
            playlist.insert(contentsOf: tracks, at: at)
            playlistDidMutate()
            playTrack(at: at)
        }
    }

    // MARK: Playlist editing (upstream's semantics)

    func clearPlaylist() {
        stop()
        playlist.removeAll()
        currentIndex = -1
        currentTrack = nil
        shuffle.clear()
        PlexPlaybackReporter.shared.stopTracking()
        SubsonicPlaybackReporter.shared.trackStopped()
        JellyfinPlaybackReporter.shared.trackStopped()
        EmbyPlaybackReporter.shared.trackStopped()
        delegate?.audioEngineDidChangePlaylist()
    }

    func removeTrack(at index: Int) {
        guard playlist.indices.contains(index) else { return }
        playlist.remove(at: index)
        if index == currentIndex {
            stop()
            currentTrack = nil
            currentIndex = playlist.isEmpty ? -1 : min(index, playlist.count - 1)
            if currentIndex >= 0 { currentTrack = playlist[currentIndex] }
        } else if index < currentIndex {
            currentIndex -= 1
        }
        playlistDidMutate()
    }

    func moveTrack(from source: Int, to destination: Int) {
        guard playlist.indices.contains(source), playlist.indices.contains(destination) else { return }
        playlist.insert(playlist.remove(at: source), at: destination)
        if source == currentIndex { currentIndex = destination }
        else if source < currentIndex && destination >= currentIndex { currentIndex -= 1 }
        else if source > currentIndex && destination <= currentIndex { currentIndex += 1 }
        playlistDidMutate()
    }

    enum SortCriteria { case title, filename, path, duration, artist, album }

    func sortPlaylist(by criteria: SortCriteria, ascending: Bool = true) {
        reorderKeepingCurrent { tracks in
            tracks.sort { a, b in
                let order: ComparisonResult
                switch criteria {
                case .title: order = a.displayTitle.localizedCaseInsensitiveCompare(b.displayTitle)
                case .filename: order = a.url.lastPathComponent.localizedCaseInsensitiveCompare(b.url.lastPathComponent)
                case .path: order = a.url.path.localizedCaseInsensitiveCompare(b.url.path)
                case .duration:
                    let x = a.duration ?? 0, y = b.duration ?? 0
                    order = x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame
                case .artist: order = (a.artist ?? "").localizedCaseInsensitiveCompare(b.artist ?? "")
                case .album: order = (a.album ?? "").localizedCaseInsensitiveCompare(b.album ?? "")
                }
                return ascending ? order == .orderedAscending : order == .orderedDescending
            }
        }
    }

    func shufflePlaylist() { reorderKeepingCurrent { $0.shuffle() } }
    func reversePlaylist() { reorderKeepingCurrent { $0.reverse() } }

    /// Reorders the queue and keeps pointing at the same current track (found by URL, as upstream).
    private func reorderKeepingCurrent(_ reorder: (inout [Track]) -> Void) {
        let currentURL = playlist.indices.contains(currentIndex) ? playlist[currentIndex].url : nil
        reorder(&playlist)
        if let currentURL { currentIndex = playlist.firstIndex { $0.url == currentURL } ?? -1 }
        playlistDidMutate()
    }

    /// -1 left … 1 right. Not persisted, as upstream.
    var balance: Float = 0 {
        didSet {
            balance = max(-1, min(1, balance))
            applyAudioFilters()
            notifyPlaybackOptionsChanged()
        }
    }

    private func playlistDidMutate() {
        if shuffleEnabled { shuffle.rebuild(count: playlist.count, anchoredAt: currentIndex) }
        replaceQueuedNext()
        delegate?.audioEngineDidChangePlaylist()
    }

    /// A `.cue` file, or an audio file with a sibling `.cue`, as its virtual tracks. Same as upstream.
    static func tracksForCueOrSibling(url: URL) -> [Track]? {
        do {
            if url.pathExtension.lowercased() == "cue" {
                return CueSheet.expandToTracks(cue: try CueSheet.parse(from: url), cueFileURL: url)
            }
            guard let sibling = CueSheet.siblingCue(for: url) else { return nil }
            return CueSheet.expandToTracks(cue: try CueSheet.parse(from: sibling), cueFileURL: sibling, backingOverride: url)
        } catch {
            NSLog("AudioEngine: cue parse failed for '%@': %@", url.lastPathComponent, error.localizedDescription)
            return nil
        }
    }

    // MARK: Transport

    func play() {
        guard !playlist.isEmpty else { return }
        if currentIndex < 0 { currentIndex = 0 }
        switch state {
        case .playing:
            return
        case .paused:
            mpv.set("pause", false)
            state = .playing
            reportResume()
        case .stopped:
            startPlayback(at: currentIndex)
        }
    }

    func pause() {
        guard state == .playing else { return }
        mpv.set("pause", true)
        state = .paused
        reportPause()
    }

    func stop() {
        guard state != .stopped || queuedNextIndex != nil else { return }
        if state != .stopped { reportStop(finished: false) }
        mpv.command("stop")
        queuedNextIndex = nil
        currentTime = 0
        mpvDuration = nil
        state = .stopped
    }

    func next() {
        guard !playlist.isEmpty else { return }
        let target = shuffleEnabled
            ? shuffle.manualNext(count: playlist.count, current: currentIndex)
            : (currentIndex + 1) % playlist.count
        guard let target else { return }
        jump(to: target)
    }

    func previous() {
        guard !playlist.isEmpty else { return }
        let target = shuffleEnabled
            ? shuffle.manualPrevious(count: playlist.count, current: currentIndex)
            : (currentIndex - 1 + playlist.count) % playlist.count
        guard let target else { return }
        jump(to: target)
    }

    func playTrack(at index: Int) {
        guard playlist.indices.contains(index) else { return }
        if shuffleEnabled { shuffle.select(index, count: playlist.count) }
        if state != .stopped { reportStop(finished: false) }
        startPlayback(at: index)
    }

    func seek(to time: TimeInterval) {
        guard state != .stopped else { return }
        let offset = currentTrack?.cueStartOffset ?? 0
        mpv.command("seek", String(max(0, time) + offset), "absolute")
        currentTime = max(0, time)
    }

    /// Next/previous keep the transport state: a paused player stays paused on the new track.
    private func jump(to index: Int) {
        let wasPlaying = state == .playing
        if state != .stopped { reportStop(finished: false) }
        startPlayback(at: index, paused: !wasPlaying && state != .stopped)
    }

    // MARK: Playback through mpv

    private func startPlayback(at index: Int, paused: Bool = false) {
        guard playlist.indices.contains(index) else { return }
        let track = playlist[index]
        currentIndex = index
        if track.isStreamingPlaceholder {
            resolvePlaceholderAndPlay(at: index)
            return
        }
        currentTime = 0
        mpvDuration = nil
        mpv.set("pause", paused)
        mpv.command("loadfile", Self.mpvTarget(track.url), "replace", "-1", Self.cueOptions(track))
        queuedNextIndex = nil
        currentTrack = track
        state = paused ? .paused : .playing
        if RadioManager.shared.isActive { RadioManager.shared.reactivateIfNeeded(for: track.url) }
        reportStart(track)
        appendNext(mode: "append")
    }

    private func resolvePlaceholderAndPlay(at index: Int) {
        let placeholder = playlist[index]
        Task { @MainActor [weak self] in
            let resolved = await StreamingTrackResolver.resolve(placeholder)
            guard let self, self.playlist.indices.contains(index), self.playlist[index].id == placeholder.id else { return }
            guard let resolved else {
                self.notifyTrackLoadFailure(placeholder, message: "Cannot refresh streaming URL for \(placeholder.title)")
                return
            }
            self.playlist[index] = resolved
            self.delegate?.audioEngineDidChangePlaylist()
            if self.currentIndex == index { self.startPlayback(at: index) }
        }
    }

    /// Index natural playback moves to after the current track, per upstream's repeat rules.
    private func naturalNextIndex() -> Int? {
        guard playlist.indices.contains(currentIndex) else { return nil }
        if repeatEnabled && !shuffleEnabled { return currentIndex }
        if shuffleEnabled {
            return shuffle.peekNext(count: playlist.count, current: currentIndex, repeating: repeatEnabled)
        }
        return currentIndex + 1 < playlist.count ? currentIndex + 1 : nil
    }

    /// Queues the follow-on file in mpv so it hands over gaplessly. mpv's playlist only ever
    /// grows between jumps (finished entries stay behind the cursor; `loadfile replace` resets it).
    /// `append-play` also starts the file if mpv already ran dry before this event reached us.
    private func appendNext(mode: String) {
        queuedNextIndex = nil
        guard state != .stopped, let next = naturalNextIndex(), !playlist[next].isStreamingPlaceholder else { return }
        if mpv.command("loadfile", Self.mpvTarget(playlist[next].url), mode, "-1", Self.cueOptions(playlist[next])) {
            queuedNextIndex = next
        }
    }

    /// Re-picks the queued file after shuffle, repeat or the playlist changed. Never clears
    /// mpv's whole playlist: mid-hand-over there is no current entry, and a clear drops the next one.
    private func replaceQueuedNext() {
        guard state != .stopped else { return }
        guard let position = mpv.int("playlist-pos"), position >= 0 else {
            pendingRequeue = true  // between files; redo it once the next one has loaded
            return
        }
        while let count = mpv.int("playlist-count"), count > position + 1 {
            mpv.command("playlist-remove", String(position + 1))
        }
        appendNext(mode: "append")
    }

    private static func mpvTarget(_ url: URL) -> String {
        url.isFileURL ? url.path : url.absoluteString
    }

    /// Per-file start/end marks for a cue track, so mpv plays just its slice of the shared file.
    /// ponytail: consecutive cue tracks reopen the file, so they are not sample-gapless yet.
    private static func cueOptions(_ track: Track) -> String {
        var options: [String] = []
        if let start = track.cueStartOffset { options.append("start=\(start)") }
        if let end = track.cueEndOffset { options.append("end=\(end)") }
        return options.joined(separator: ",")
    }

    private func handle(_ event: MpvPlayer.Event) {
        switch event {
        case .fileLoaded:
            mpvDuration = mpv.double("duration")
            if pendingRequeue {
                pendingRequeue = false
                replaceQueuedNext()
            }
            if RadioManager.shared.isActive { RadioManager.shared.streamDidConnect() }
        case .endFile(let reason, let error):
            switch reason {
            case .eof: trackDidFinish()
            case .error: trackDidFail(error)
            default: break
            }
        case .property("time-pos", let value):
            guard let time = value as? Double else { return }
            currentTime = max(0, time - (currentTrack?.cueStartOffset ?? 0))
            if Date().timeIntervalSince(lastTimeReport) >= 0.25 { reportTime() }
        case .property("duration", let value):
            mpvDuration = value as? Double
        case .property("metadata", let value):
            guard RadioManager.shared.isActive, let map = value as? [String: Any] else { return }
            RadioManager.shared.streamDidReceiveMetadata(map.compactMapValues { $0 as? String })
        default:
            break
        }
    }

    private func trackDidFinish() {
        guard let finished = currentTrack, state != .stopped else { return }
        currentTime = duration  // the file ran out, whatever the last throttled position said
        NotificationCenter.default.post(name: .audioTrackDidFinishNaturally, object: self, userInfo: ["track": finished])
        reportStop(finished: true)
        recordPlayed(finished)

        guard let next = queuedNextIndex else {
            NotificationCenter.default.post(name: .audioQueueDidExhaust, object: self)
            queuedNextIndex = nil
            currentTime = 0
            state = .stopped
            return
        }
        // mpv is already playing the queued file; catch the queue up to it.
        if shuffleEnabled { shuffle.commitAdvance(to: next, count: playlist.count, current: currentIndex) }
        currentIndex = next
        currentTime = 0
        mpvDuration = nil
        currentTrack = playlist[next]
        reportStart(playlist[next])
        appendNext(mode: "append-play")
    }

    private func trackDidFail(_ message: String?) {
        guard let track = currentTrack else { return }
        notifyTrackLoadFailure(track, message: message ?? "Playback failed")
        if RadioManager.shared.isActive {
            RadioManager.shared.streamDidDisconnect(error: NSError(domain: "AudioEngine", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message ?? "Stream failed"]))
        }
        delegate?.audioEngineDidEncounterPlaybackError()
        queuedNextIndex = nil
        state = .stopped
        // Same recovery as upstream's streaming errors: try the next track once things settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.state == .stopped, self.playlist.count > 1 else { return }
            self.next()
        }
    }

    private func notifyTrackLoadFailure(_ track: Track, message: String) {
        let error = NSError(domain: "AudioEngine", code: 1002, userInfo: [NSLocalizedDescriptionKey: message])
        delegate?.audioEngineDidFailToLoadTrack(track, error: error)
        NotificationCenter.default.post(name: .audioTrackDidFailToLoad, object: self,
                                        userInfo: ["track": track, "error": error, "message": message])
    }

    private func notifyPlaybackOptionsChanged() {
        NotificationCenter.default.post(name: .audioPlaybackOptionsChanged, object: self)
    }

    private func stopRadioIfLoadingNonRadioContent(incomingTrackURL: URL?) {
        let radio = RadioManager.shared
        guard radio.isActive else { return }
        if let station = radio.currentStation?.url, station == incomingTrackURL { return }
        radio.stop()
    }

    // MARK: Equalizer (upstream band layout as ffmpeg shelf/peaking filters)

    func setEQBand(_ band: Int, gain: Float) {
        guard eqGains.indices.contains(band) else { return }
        eqGains[band] = max(-12, min(12, gain))
        applyAudioFilters()
    }

    func getEQBand(_ band: Int) -> Float { eqGains.indices.contains(band) ? eqGains[band] : 0 }

    func setPreamp(_ gain: Float) {
        preampGain = max(-12, min(12, gain))
        applyAudioFilters()
    }

    func getPreamp() -> Float { preampGain }

    func setEQEnabled(_ enabled: Bool) {
        eqEnabled = enabled
        applyAudioFilters()
    }

    func isEQEnabled() -> Bool { eqEnabled }

    /// Switches between the classic 10-band and modern 21-band layouts, remapping the curve.
    func applyEQLayout(_ layout: EQConfiguration) {
        guard layout != activeEQConfiguration else { return }
        eqGains = layout.gainValues(remapping: eqGains, from: activeEQConfiguration)
        activeEQConfiguration = layout
        applyAudioFilters()
    }

    // MARK: Reference Tuning and speed

    func setTuningPreset(_ preset: PitchTuningController.Preset, persist: Bool = true) {
        tuningController.applyPreset(preset)
        if persist { tuningController.saveToDefaults() }
        applyAudioFilters()
    }

    func setTuningOffsetCents(_ cents: Double, persist: Bool = true) {
        let source = 440.0
        tuningController.applyPreset(.custom(source: source, target: source * pow(2.0, cents / 1200.0)))
        if persist { tuningController.saveToDefaults() }
        applyAudioFilters()
    }

    func setTuningEnabled(_ enabled: Bool, persist: Bool = true) {
        tuningController.setEnabled(enabled)
        if persist { tuningController.saveToDefaults() }
        applyAudioFilters()
    }

    var playbackSpeed: Float { tuningController.rate }

    func setPlaybackSpeed(_ value: Float, persist: Bool = true) {
        tuningController.setRate(value)
        if persist { tuningController.saveToDefaults() }
        applyAudioFilters()
    }

    // ponytail: rebuilds the whole chain per change (a brief glitch); move gain changes to
    // `af-command` on labelled filters when a GUI slider drives them continuously.
    private func applyAudioFilters() {
        var filters: [String] = []
        let cents = tuningController.enabled ? tuningController.appliedCents : 0
        if cents != 0 {
            filters.append("rubberband=pitch-scale=\(pow(2.0, cents / 1200.0))")
        }
        if eqEnabled {
            if preampGain != 0 { filters.append("lavfi=[volume=\(preampGain)dB]") }
            for (setting, gain) in zip(EQBandProgram.program(for: activeEQConfiguration), eqGains) where gain != 0 {
                let kind: String
                switch setting.role {
                case .lowShelf: kind = "lowshelf"
                case .highShelf: kind = "highshelf"
                case .parametric: kind = "equalizer"
                case .bypassed: continue
                }
                filters.append("lavfi=[\(kind)=f=\(setting.frequency):t=o:w=\(setting.bandwidth):g=\(gain)]")
            }
        }
        if balance != 0 {
            // Equal-power-free linear pan, as AVAudioPlayerNode.pan: the far side fades out.
            let left = balance > 0 ? 1 - Double(balance) : 1, right = balance < 0 ? 1 + Double(balance) : 1
            filters.append("lavfi=[pan=stereo|c0=\(left)*c0|c1=\(right)*c1]")
        }
        mpv.set("af", filters.joined(separator: ","))
        mpv.set("speed", Double(tuningController.rate))
    }

    // MARK: Output device

    @discardableResult
    func setOutputDevice(_ deviceID: AudioDeviceID?) -> Bool {
        let name = deviceID.flatMap { AudioOutputManager.shared.mpvDeviceName(for: $0) } ?? "auto"
        return mpv.set("audio-device", name)
    }

    var mpvAudioDevices: [[String: Any]] { mpv.node("audio-device-list") as? [[String: Any]] ?? [] }

    // MARK: Analysis consumers
    // ponytail: counted only; PCM/spectrum taps (from a PipeWire monitor of mpv's stream) arrive
    // with the visualizer stage, and these counts will gate that capture.

    private var fullStereoConsumers: [String: Int] = [:]

    func addFullStereoConsumer(_ id: String) { fullStereoConsumers[id, default: 0] += 1 }

    func removeFullStereoConsumer(_ id: String) {
        guard let count = fullStereoConsumers[id] else { return }
        fullStereoConsumers[id] = count > 1 ? count - 1 : nil
    }

    var fullStereoNeeded: Bool { !fullStereoConsumers.isEmpty }

    // MARK: Casting (not on Linux yet)

    var isCastingActive: Bool { false }
    var isAudioCastRoutingActive: Bool { false }
    var isAnyCastingActive: Bool { false }

    // MARK: Server reporting and history (same hooks as upstream)

    private func reportStart(_ track: Track) {
        PlexPlaybackReporter.shared.trackDidStart(track, at: 0)
        guard let length = track.duration else { return }
        if let id = track.subsonicId, let server = track.subsonicServerId {
            SubsonicPlaybackReporter.shared.trackStarted(trackId: id, serverId: server, duration: length)
        }
        if let id = track.jellyfinId, let server = track.jellyfinServerId {
            JellyfinPlaybackReporter.shared.trackStarted(trackId: id, serverId: server, duration: length)
        }
        if let id = track.embyId, let server = track.embyServerId {
            EmbyPlaybackReporter.shared.trackStarted(trackId: id, serverId: server, duration: length)
        }
    }

    private func reportPause() {
        PlexPlaybackReporter.shared.trackDidPause(at: currentTime)
        SubsonicPlaybackReporter.shared.trackPaused()
        JellyfinPlaybackReporter.shared.trackPaused()
        EmbyPlaybackReporter.shared.trackPaused()
    }

    private func reportResume() {
        PlexPlaybackReporter.shared.trackDidResume(at: currentTime)
        SubsonicPlaybackReporter.shared.trackResumed()
        JellyfinPlaybackReporter.shared.trackResumed()
        EmbyPlaybackReporter.shared.trackResumed()
    }

    private func reportStop(finished: Bool) {
        PlexPlaybackReporter.shared.trackDidStop(at: finished ? duration : currentTime, finished: finished)
        SubsonicPlaybackReporter.shared.trackStopped()
        JellyfinPlaybackReporter.shared.trackStopped()
        EmbyPlaybackReporter.shared.trackStopped()
    }

    private func reportTime() {
        lastTimeReport = Date()
        let current = currentTime, length = duration
        delegate?.audioEngineDidUpdateTime(current: current, duration: length)
        PlexPlaybackReporter.shared.updatePosition(current)
        guard let track = currentTrack else { return }
        if let id = track.subsonicId, let server = track.subsonicServerId {
            SubsonicPlaybackReporter.shared.updatePlayback(trackId: id, serverId: server, position: current, duration: length)
        }
        if let id = track.jellyfinId, let server = track.jellyfinServerId {
            JellyfinPlaybackReporter.shared.updatePlayback(trackId: id, serverId: server, position: current, duration: length)
        }
        if let id = track.embyId, let server = track.embyServerId {
            EmbyPlaybackReporter.shared.updatePlayback(trackId: id, serverId: server, position: current, duration: length)
        }
    }

    private func recordPlayed(_ track: Track) {
        switch track.playHistorySource {
        case .plex: PlexRadioHistory.shared.recordTrackPlayed(track)
        case .subsonic: SubsonicRadioHistory.shared.recordTrackPlayed(track)
        case .jellyfin: JellyfinRadioHistory.shared.recordTrackPlayed(track)
        case .emby: EmbyRadioHistory.shared.recordTrackPlayed(track)
        case .local, .radio, .youtube: LocalRadioHistory.shared.recordTrackPlayed(track)
        }
        let eventId = MediaLibraryStore.shared.insertPlayEvent(
            trackId: track.playHistoryTrackIdentifier,
            trackURL: track.url.isFileURL ? track.url.absoluteString : nil,
            title: track.title, artist: track.artist, album: track.album, genre: track.genre,
            playedAt: Date(), durationListened: track.duration ?? 0,
            source: track.playHistorySource.rawValue, skipped: false,
            outputDevice: CastManager.currentPlaybackDeviceName)
        if let eventId, track.genre?.isEmpty ?? true {
            Task.detached(priority: .utility) {
                await GenreDiscoveryService.shared.enrichPlayEvent(
                    id: eventId, title: track.title, artist: track.artist, album: track.album)
            }
        }
    }
}
