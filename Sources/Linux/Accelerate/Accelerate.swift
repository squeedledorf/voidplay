// Linux stand-in for the slice of Apple's Accelerate (vDSP) that Voidplay's Linux
// targets call. Named `Accelerate` so upstream files keep `import Accelerate` unchanged.
// Semantics follow Apple's documentation: unscaled forward DFT, strided vector ops.
// ponytail: only the functions the Linux targets reference; add more as targets port over.

import Foundation

public typealias vDSP_Length = UInt
public typealias vDSP_Stride = Int

public enum vDSP_DFT_Direction: Int32 {
    case FORWARD = 1
    case INVERSE = -1
}

/// Complex-to-complex DFT plan. Power-of-two sizes only (Apple also takes f·2^k for f in 3/5/15;
/// nothing on Linux asks for those yet).
public final class vDSP_DFT_SetupStorage {
    let n: Int
    let bitReverse: [Int]
    let cosTable: [Float]
    let sinTable: [Float]

    init?(n: Int, direction: vDSP_DFT_Direction) {
        guard n >= 2, n & (n - 1) == 0 else { return nil }
        self.n = n
        let bits = n.trailingZeroBitCount
        bitReverse = (0..<n).map { i in
            var r = 0
            for b in 0..<bits where i & (1 << b) != 0 { r |= 1 << (bits - 1 - b) }
            return r
        }
        let sign: Double = direction == .FORWARD ? -1 : 1
        cosTable = (0..<n / 2).map { Float(cos(2 * Double.pi * Double($0) / Double(n))) }
        sinTable = (0..<n / 2).map { Float(sign * sin(2 * Double.pi * Double($0) / Double(n))) }
    }
}

public typealias vDSP_DFT_Setup = vDSP_DFT_SetupStorage

public func vDSP_DFT_zop_CreateSetup(_ previous: vDSP_DFT_Setup?, _ length: vDSP_Length,
                                     _ direction: vDSP_DFT_Direction) -> vDSP_DFT_Setup? {
    vDSP_DFT_SetupStorage(n: Int(length), direction: direction)
}

public func vDSP_DFT_DestroySetup(_ setup: vDSP_DFT_Setup?) {}

/// Iterative radix-2 FFT. Inputs and outputs may alias, as Apple allows.
public func vDSP_DFT_Execute(_ setup: vDSP_DFT_Setup,
                             _ ir: UnsafePointer<Float>, _ ii: UnsafePointer<Float>,
                             _ or: UnsafeMutablePointer<Float>, _ oi: UnsafeMutablePointer<Float>) {
    let n = setup.n
    var re = [Float](repeating: 0, count: n)
    var im = [Float](repeating: 0, count: n)
    for i in 0..<n {
        re[setup.bitReverse[i]] = ir[i]
        im[setup.bitReverse[i]] = ii[i]
    }
    var size = 2
    while size <= n {
        let half = size / 2
        let step = n / size
        var start = 0
        while start < n {
            for k in 0..<half {
                let c = setup.cosTable[k * step], s = setup.sinTable[k * step]
                let a = start + k, b = a + half
                let tr = re[b] * c - im[b] * s
                let ti = re[b] * s + im[b] * c
                re[b] = re[a] - tr; im[b] = im[a] - ti
                re[a] += tr; im[a] += ti
            }
            start += size
        }
        size *= 2
    }
    for i in 0..<n {
        or[i] = re[i]
        oi[i] = im[i]
    }
}

/// Maximum magnitude.
public func vDSP_maxmgv(_ a: UnsafePointer<Float>, _ stride: vDSP_Stride,
                        _ c: UnsafeMutablePointer<Float>, _ n: vDSP_Length) {
    var m: Float = 0
    for i in 0..<Int(n) { m = max(m, abs(a[i * stride])) }
    c.pointee = m
}

/// Sum of squares.
public func vDSP_svesq(_ a: UnsafePointer<Float>, _ stride: vDSP_Stride,
                       _ c: UnsafeMutablePointer<Float>, _ n: vDSP_Length) {
    var s: Float = 0
    for i in 0..<Int(n) { s += a[i * stride] * a[i * stride] }
    c.pointee = s
}

/// Mean. Zero for an empty vector, as Apple returns.
public func vDSP_meanv(_ a: UnsafePointer<Float>, _ stride: vDSP_Stride,
                       _ c: UnsafeMutablePointer<Float>, _ n: vDSP_Length) {
    var s: Float = 0
    for i in 0..<Int(n) { s += a[i * stride] }
    c.pointee = n == 0 ? 0 : s / Float(n)
}

// MARK: Windows and element-wise ops (the visualization tap)

public let vDSP_HANN_NORM: Int32 = 0
public let vDSP_HANN_DENORM: Int32 = 1
public let vDSP_HALF_WINDOW: Int32 = 4

/// Hann window: 0.5·(1 − cos 2πn/N), or 0.8165·(1 − cos 2πn/N) normalised (RMS 1), as Apple's.
public func vDSP_hann_window(_ c: UnsafeMutablePointer<Float>, _ n: vDSP_Length, _ flag: Int32) {
    let count = Int(n)
    let scale: Float = flag & vDSP_HANN_DENORM != 0 ? 0.5 : 0.8165
    let length = flag & vDSP_HALF_WINDOW != 0 ? (count + 1) / 2 : count
    for i in 0..<length { c[i] = scale * (1 - Float(cos(2 * Double.pi * Double(i) / Double(count)))) }
}

/// C[i] = A[i] · B[i]
public func vDSP_vmul(_ a: UnsafePointer<Float>, _ ia: vDSP_Stride, _ b: UnsafePointer<Float>, _ ib: vDSP_Stride,
                      _ c: UnsafeMutablePointer<Float>, _ ic: vDSP_Stride, _ n: vDSP_Length) {
    for i in 0..<Int(n) { c[i * ic] = a[i * ia] * b[i * ib] }
}

/// C[i] = α·log10(A[i] / B), α = 10 for power (F = 0), 20 for amplitude (F = 1).
public func vDSP_vdbcon(_ a: UnsafePointer<Float>, _ ia: vDSP_Stride, _ b: UnsafePointer<Float>,
                        _ c: UnsafeMutablePointer<Float>, _ ic: vDSP_Stride, _ n: vDSP_Length, _ f: UInt32) {
    let alpha: Float = f == 0 ? 10 : 20
    for i in 0..<Int(n) { c[i * ic] = alpha * log10(a[i * ia] / b.pointee) }
}

// MARK: More element-wise ops (WMP outline feathering)

public func vDSP_vclr(_ c: UnsafeMutablePointer<Float>, _ ic: vDSP_Stride, _ n: vDSP_Length) {
    for i in 0..<Int(n) { c[i * ic] = 0 }
}

/// C[i] = max(A[i], B[i])
public func vDSP_vmax(_ a: UnsafePointer<Float>, _ ia: vDSP_Stride, _ b: UnsafePointer<Float>, _ ib: vDSP_Stride,
                      _ c: UnsafeMutablePointer<Float>, _ ic: vDSP_Stride, _ n: vDSP_Length) {
    for i in 0..<Int(n) { c[i * ic] = max(a[i * ia], b[i * ib]) }
}

/// D[i] = A[i] >= B ? C : −C
public func vDSP_vthrsc(_ a: UnsafePointer<Float>, _ ia: vDSP_Stride, _ b: UnsafePointer<Float>,
                        _ c: UnsafePointer<Float>, _ d: UnsafeMutablePointer<Float>, _ id: vDSP_Stride, _ n: vDSP_Length) {
    for i in 0..<Int(n) { d[i * id] = a[i * ia] >= b.pointee ? c.pointee : -c.pointee }
}

/// C[i] = A[i] + B
public func vDSP_vsadd(_ a: UnsafePointer<Float>, _ ia: vDSP_Stride, _ b: UnsafePointer<Float>,
                       _ c: UnsafeMutablePointer<Float>, _ ic: vDSP_Stride, _ n: vDSP_Length) {
    for i in 0..<Int(n) { c[i * ic] = a[i * ia] + b.pointee }
}

/// C = Σ A[i]
public func vDSP_sve(_ a: UnsafePointer<Float>, _ ia: vDSP_Stride, _ c: UnsafeMutablePointer<Float>, _ n: vDSP_Length) {
    var sum: Float = 0
    for i in 0..<Int(n) { sum += a[i * ia] }
    c.pointee = sum
}

/// C[i] = A + i·B
public func vDSP_vramp(_ a: UnsafePointer<Float>, _ b: UnsafePointer<Float>, _ c: UnsafeMutablePointer<Float>,
                       _ ic: vDSP_Stride, _ n: vDSP_Length) {
    for i in 0..<Int(n) { c[i * ic] = a.pointee + Float(i) * b.pointee }
}

/// C[i] = |A[i]|
public func vDSP_vabs(_ a: UnsafePointer<Float>, _ ia: vDSP_Stride, _ c: UnsafeMutablePointer<Float>,
                      _ ic: vDSP_Stride, _ n: vDSP_Length) {
    for i in 0..<Int(n) { c[i * ic] = abs(a[i * ia]) }
}

/// Packs A[i] where B[i] ≠ 0 into C, in order.
public func vDSP_vcmprs(_ a: UnsafePointer<Float>, _ ia: vDSP_Stride, _ b: UnsafePointer<Float>, _ ib: vDSP_Stride,
                        _ c: UnsafeMutablePointer<Float>, _ ic: vDSP_Stride, _ n: vDSP_Length) {
    var out = 0
    for i in 0..<Int(n) where b[i * ib] != 0 {
        c[out * ic] = a[i * ia]
        out += 1
    }
}

// MARK: Classic real FFT (vDSP_create_fftsetup / vDSP_fft_zrip), as the .wal analyzer uses it

public typealias FFTRadix = Int32
public typealias FFTDirection = Int32
public let kFFTRadix2: Int32 = 0
public let FFT_FORWARD: Int32 = 1
public let FFT_INVERSE: Int32 = -1

public struct DSPComplex { public var real: Float; public var imag: Float
    public init(real: Float = 0, imag: Float = 0) { self.real = real; self.imag = imag } }
public struct DSPSplitComplex {
    public var realp: UnsafeMutablePointer<Float>
    public var imagp: UnsafeMutablePointer<Float>
    public init(realp: UnsafeMutablePointer<Float>, imagp: UnsafeMutablePointer<Float>) { self.realp = realp; self.imagp = imagp }
}

public final class FFTSetupStorage {
    let log2n: Int
    let forward: vDSP_DFT_Setup
    let inverse: vDSP_DFT_Setup
    init?(log2n: Int) {
        let n = vDSP_Length(1 << log2n)
        guard let f = vDSP_DFT_zop_CreateSetup(nil, n, .FORWARD), let i = vDSP_DFT_zop_CreateSetup(nil, n, .INVERSE) else { return nil }
        self.log2n = log2n; forward = f; inverse = i
    }
}
public typealias FFTSetup = FFTSetupStorage

public func vDSP_create_fftsetup(_ log2n: vDSP_Length, _ radix: FFTRadix) -> FFTSetup? { FFTSetupStorage(log2n: Int(log2n)) }
public func vDSP_destroy_fftsetup(_ setup: FFTSetup?) {}

/// Interleaved complex → split complex. `ic` counts floats (2 = consecutive elements), as Apple's.
public func vDSP_ctoz(_ c: UnsafePointer<DSPComplex>, _ ic: vDSP_Stride, _ z: UnsafePointer<DSPSplitComplex>,
                      _ iz: vDSP_Stride, _ n: vDSP_Length) {
    for i in 0..<Int(n) {
        let element = c[i * ic / 2]
        z.pointee.realp[i * iz] = element.real
        z.pointee.imagp[i * iz] = element.imag
    }
}

/// Apple's packed in-place real FFT: for N = 2^log2n real samples held as N/2 split pairs, leaves
/// 2·X[k] for k in 1..<N/2, with 2·X[0] in realp[0] and 2·X[N/2] in imagp[0].
/// ponytail: forward only (the only direction upstream uses); computed through the complex DFT.
public func vDSP_fft_zrip(_ setup: FFTSetup, _ c: UnsafePointer<DSPSplitComplex>, _ ic: vDSP_Stride,
                          _ log2n: vDSP_Length, _ direction: FFTDirection) {
    let n = 1 << Int(log2n), half = n / 2
    let split = c.pointee
    var re = [Float](repeating: 0, count: n), im = [Float](repeating: 0, count: n)
    for i in 0..<half {
        re[2 * i] = split.realp[i * ic]
        re[2 * i + 1] = split.imagp[i * ic]
    }
    var outRe = [Float](repeating: 0, count: n), outIm = [Float](repeating: 0, count: n)
    vDSP_DFT_Execute(setup.forward, re, im, &outRe, &outIm)
    split.realp[0] = 2 * outRe[0]
    split.imagp[0] = 2 * outRe[half]
    for k in 1..<half {
        split.realp[k * ic] = 2 * outRe[k]
        split.imagp[k * ic] = 2 * outIm[k]
    }
}

/// C[i] = |A[i]| for split complex A.
public func vDSP_zvabs(_ a: UnsafePointer<DSPSplitComplex>, _ ia: vDSP_Stride, _ c: UnsafeMutablePointer<Float>,
                       _ ic: vDSP_Stride, _ n: vDSP_Length) {
    for i in 0..<Int(n) {
        let r = a.pointee.realp[i * ia], m = a.pointee.imagp[i * ia]
        c[i * ic] = (r * r + m * m).squareRoot()
    }
}

/// C[i] = A[i] · B
public func vDSP_vsmul(_ a: UnsafePointer<Float>, _ ia: vDSP_Stride, _ b: UnsafePointer<Float>,
                       _ c: UnsafeMutablePointer<Float>, _ ic: vDSP_Stride, _ n: vDSP_Length) {
    for i in 0..<Int(n) { c[i * ic] = a[i * ia] * b.pointee }
}
