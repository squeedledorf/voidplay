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
