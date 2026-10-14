import Foundation

public final class CGColorSpace: @unchecked Sendable {
    public let name: String
    public init?(name: String) { self.name = name }
    public static let sRGB = "kCGColorSpaceSRGB"
    public static let linearGray = "kCGColorSpaceLinearGray"
    public static let genericGrayGamma2_2 = "kCGColorSpaceGenericGrayGamma2_2"
    public static let genericRGBLinear = "kCGColorSpaceGenericRGBLinear"
    public static let deviceRGB = CGColorSpace(name: "kCGColorSpaceDeviceRGB")!
    public var numberOfComponents: Int { name.contains("Gray") ? 1 : 3 }
    public var model: CGColorSpaceModel { name.contains("Gray") ? .monochrome : .rgb }
}

public enum CGColorSpaceModel: Int32, Sendable {
    case unknown = -1, monochrome, rgb, cmyk, lab, deviceN, indexed, pattern, XYZ
}

public func CGColorSpaceCreateDeviceRGB() -> CGColorSpace { .deviceRGB }
public func CGColorSpaceCreateDeviceGray() -> CGColorSpace { CGColorSpace(name: "kCGColorSpaceDeviceGray")! }

public enum CGColorRenderingIntent: Int32, Sendable {
    case defaultIntent, absoluteColorimetric, relativeColorimetric, perceptual, saturation
}

/// An sRGB colour with alpha.
public final class CGColor: @unchecked Sendable, Equatable {
    public let components: [CGFloat]?
    public var alpha: CGFloat { components?.last ?? 1 }
    public var numberOfComponents: Int { components?.count ?? 0 }

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        components = [red, green, blue, alpha]
    }

    public convenience init(gray: CGFloat, alpha: CGFloat) {
        self.init(red: gray, green: gray, blue: gray, alpha: alpha)
    }

    public convenience init(srgbRed red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }

    public func copy(alpha: CGFloat) -> CGColor? {
        let c = rgba
        return CGColor(red: c.r, green: c.g, blue: c.b, alpha: alpha)
    }

    public static func == (lhs: CGColor, rhs: CGColor) -> Bool { lhs.components == rhs.components }

    public static let black = CGColor(gray: 0, alpha: 1)
    public static let white = CGColor(gray: 1, alpha: 1)
    public static let clear = CGColor(gray: 0, alpha: 0)

    public var rgba: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        guard let c = components, c.count >= 4 else { return (0, 0, 0, 1) }
        return (c[0], c[1], c[2], c[3])
    }
}
