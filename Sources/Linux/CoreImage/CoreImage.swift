import Foundation
import CoreGraphics

// Linux stand-in for the slice of Core Image upstream uses: a .wal skin's colour themes (gammaset)
// recolour sprites with CIColorControls (saturation) and CIColorMatrix (per-channel scale/offset).
// Filters run on the CPU over unpremultiplied colour, alpha untouched, as Core Image does.
//
// ponytail: only those two filters; anything else passes the image through unchanged.

public let kCIInputSaturationKey = "inputSaturation"
public let kCIInputImageKey = "inputImage"

public struct CIVector: Sendable {
    public let x: CGFloat, y: CGFloat, z: CGFloat, w: CGFloat
    public init(x: CGFloat, y: CGFloat, z: CGFloat, w: CGFloat) { self.x = x; self.y = y; self.z = z; self.w = w }
    public init(x: CGFloat, y: CGFloat, z: CGFloat) { self.init(x: x, y: y, z: z, w: 0) }
    fileprivate var values: [Float] { [Float(x), Float(y), Float(z), Float(w)] }
}

public final class CIImage: @unchecked Sendable {
    /// One pixel transform: unpremultiplied RGBA in, out (0...1).
    typealias Operation = (inout SIMD4<Float>) -> Void
    let source: CGImage
    let operations: [Operation]

    public init(cgImage: CGImage) { source = cgImage; operations = [] }
    private init(source: CGImage, operations: [Operation]) { self.source = source; self.operations = operations }

    public var extent: CGRect { CGRect(x: 0, y: 0, width: source.width, height: source.height) }

    public func applyingFilter(_ name: String, parameters: [String: Any] = [:]) -> CIImage {
        switch name {
        case "CIColorControls":
            let saturation = Float((parameters[kCIInputSaturationKey] as? Int).map(Double.init) ?? (parameters[kCIInputSaturationKey] as? NSNumber)?.doubleValue
                ?? (parameters[kCIInputSaturationKey] as? Double) ?? 1)
            return CIImage(source: source, operations: operations + [{ p in
                let luma = 0.2125 * p.x + 0.7154 * p.y + 0.0721 * p.z
                p.x = luma + (p.x - luma) * saturation
                p.y = luma + (p.y - luma) * saturation
                p.z = luma + (p.z - luma) * saturation
            }])
        case "CIColorMatrix":
            func vector(_ key: String, _ fallback: [Float]) -> SIMD4<Float> {
                let v = (parameters[key] as? CIVector)?.values ?? fallback
                return SIMD4(v[0], v[1], v[2], v[3])
            }
            let r = vector("inputRVector", [1, 0, 0, 0]), g = vector("inputGVector", [0, 1, 0, 0])
            let b = vector("inputBVector", [0, 0, 1, 0]), a = vector("inputAVector", [0, 0, 0, 1])
            let bias = vector("inputBiasVector", [0, 0, 0, 0])
            return CIImage(source: source, operations: operations + [{ p in
                p = SIMD4((r * p).sum(), (g * p).sum(), (b * p).sum(), (a * p).sum()) + bias
            }])
        default:
            return self
        }
    }

    /// The filtered pixels as a CGImage.
    func render() -> CGImage? {
        guard !operations.isEmpty else { return source }
        let width = source.width, height = source.height
        let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return nil }
        ctx.setBlendMode(.copy)
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Read after drawing: `data` hands out the pixels in this layout, current as of now.
        guard let bytes = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        for i in stride(from: 0, to: width * height * 4, by: 4) {
            let alpha = Float(bytes[i + 3]) / 255
            guard alpha > 0 else { continue }
            var p = SIMD4(Float(bytes[i]) / 255 / alpha, Float(bytes[i + 1]) / 255 / alpha,
                          Float(bytes[i + 2]) / 255 / alpha, alpha)
            for operation in operations { operation(&p) }
            p = p.clamped(lowerBound: .zero, upperBound: .one)
            bytes[i] = UInt8((p.x * p.w * 255).rounded())
            bytes[i + 1] = UInt8((p.y * p.w * 255).rounded())
            bytes[i + 2] = UInt8((p.z * p.w * 255).rounded())
            bytes[i + 3] = UInt8((p.w * 255).rounded())
        }
        return ctx.makeImage()
    }
}

public struct CIContextOption: Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let cacheIntermediates = CIContextOption(rawValue: "kCIContextCacheIntermediates")
    public static let useSoftwareRenderer = CIContextOption(rawValue: "kCIContextUseSoftwareRenderer")
}

public final class CIContext: @unchecked Sendable {
    public init(options: [CIContextOption: Any]? = nil) {}
    public func createCGImage(_ image: CIImage, from rect: CGRect) -> CGImage? {
        guard let full = image.render() else { return nil }
        return rect == image.extent ? full : full.cropping(to: rect)
    }
}
