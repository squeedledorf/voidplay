import Foundation
import CoreGraphics

// The slice of vImage upstream uses (WMP skin sprites and outline feathering), in plain Swift.
// Scaling goes through the Cairo-backed CoreGraphics with its best filter rather than vImage's
// Lanczos kernel. ponytail: per-pixel loops; fine at skin-sprite sizes.

public typealias vImagePixelCount = UInt
public typealias vImage_Flags = UInt32
public typealias vImage_Error = Int

public let kvImageNoError: vImage_Error = 0
public let kvImageInvalidParameter: vImage_Error = -21_772
public let kvImageMemoryAllocationError: vImage_Error = -21_771
public let kvImageNoFlags: UInt32 = 0
public let kvImageLeaveAlphaUnchanged: UInt32 = 1
public let kvImageCopyInPlace: UInt32 = 2
public let kvImageBackgroundColorFill: UInt32 = 4
public let kvImageEdgeExtend: UInt32 = 8
public let kvImageHighQualityResampling: UInt32 = 32

public struct vImage_Buffer {
    public var data: UnsafeMutableRawPointer!
    public var height: vImagePixelCount
    public var width: vImagePixelCount
    public var rowBytes: Int
    public init() { data = nil; height = 0; width = 0; rowBytes = 0 }
    public init(data: UnsafeMutableRawPointer!, height: vImagePixelCount, width: vImagePixelCount, rowBytes: Int) {
        self.data = data; self.height = height; self.width = width; self.rowBytes = rowBytes
    }
}

public struct vImage_CGImageFormat {
    public var bitsPerComponent: UInt32
    public var bitsPerPixel: UInt32
    public var colorSpace: Unmanaged<CGColorSpace>?
    public var bitmapInfo: CGBitmapInfo
    public var version: UInt32
    public var decode: UnsafePointer<CGFloat>?
    public var renderingIntent: CGColorRenderingIntent
    public init(bitsPerComponent: UInt32, bitsPerPixel: UInt32, colorSpace: Unmanaged<CGColorSpace>?,
                bitmapInfo: CGBitmapInfo, version: UInt32, decode: UnsafePointer<CGFloat>?,
                renderingIntent: CGColorRenderingIntent) {
        self.bitsPerComponent = bitsPerComponent; self.bitsPerPixel = bitsPerPixel
        self.colorSpace = colorSpace; self.bitmapInfo = bitmapInfo; self.version = version
        self.decode = decode; self.renderingIntent = renderingIntent
    }
}

public func vImageBuffer_Init(_ buffer: UnsafeMutablePointer<vImage_Buffer>, _ height: vImagePixelCount,
                              _ width: vImagePixelCount, _ pixelBits: UInt32, _ flags: vImage_Flags) -> vImage_Error {
    let rowBytes = (Int(width) * Int(pixelBits) + 7) / 8
    guard height > 0, width > 0, let data = calloc(Int(height), rowBytes) else { return kvImageMemoryAllocationError }
    buffer.pointee = vImage_Buffer(data: data, height: height, width: width, rowBytes: rowBytes)
    return kvImageNoError
}

/// A context drawing straight into a 32-bit buffer in `format`'s layout.
private func context(over buffer: vImage_Buffer, _ format: vImage_CGImageFormat) -> CGContext? {
    CGContext(data: buffer.data, width: Int(buffer.width), height: Int(buffer.height), bitsPerComponent: 8,
              bytesPerRow: buffer.rowBytes, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: format.bitmapInfo.rawValue)
}

public func vImageBuffer_InitWithCGImage(_ buffer: UnsafeMutablePointer<vImage_Buffer>,
                                         _ format: UnsafeMutablePointer<vImage_CGImageFormat>,
                                         _ background: UnsafePointer<CGFloat>?, _ image: CGImage,
                                         _ flags: vImage_Flags) -> vImage_Error {
    let status = vImageBuffer_Init(buffer, vImagePixelCount(image.height), vImagePixelCount(image.width), 32, flags)
    guard status == kvImageNoError else { return status }
    guard let ctx = context(over: buffer.pointee, format.pointee) else { return kvImageInvalidParameter }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    ctx.flush()
    return kvImageNoError
}

public func vImageCreateCGImageFromBuffer(_ buffer: UnsafePointer<vImage_Buffer>,
                                          _ format: UnsafeMutablePointer<vImage_CGImageFormat>,
                                          _ callback: Any?, _ userData: UnsafeMutableRawPointer?,
                                          _ flags: vImage_Flags, _ error: UnsafeMutablePointer<vImage_Error>?) -> Unmanaged<CGImage>? {
    let b = buffer.pointee
    let data = Data(bytes: b.data, count: Int(b.height) * b.rowBytes)
    guard let provider = CGDataProvider(data: data),
          let image = CGImage(width: Int(b.width), height: Int(b.height), bitsPerComponent: 8, bitsPerPixel: 32,
                              bytesPerRow: b.rowBytes, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: format.pointee.bitmapInfo, provider: provider, decode: nil,
                              shouldInterpolate: true, intent: .defaultIntent) else {
        error?.pointee = kvImageInvalidParameter
        return nil
    }
    error?.pointee = kvImageNoError
    return Unmanaged.passRetained(image)
}

/// Resamples a 32-bit RGBA (premultiplied, R first in memory) buffer to the destination's size.
public func vImageScale_ARGB8888(_ src: UnsafePointer<vImage_Buffer>, _ dest: UnsafePointer<vImage_Buffer>,
                                 _ tempBuffer: UnsafeMutableRawPointer?, _ flags: vImage_Flags) -> vImage_Error {
    let format = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: nil,
        bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
        version: 0, decode: nil, renderingIntent: .defaultIntent)
    var f = format
    guard let image = vImageCreateCGImageFromBuffer(src, &f, nil, nil, 0, nil)?.takeRetainedValue(),
          let ctx = context(over: dest.pointee, format) else { return kvImageInvalidParameter }
    ctx.interpolationQuality = .high
    ctx.setBlendMode(.copy)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: Int(dest.pointee.width), height: Int(dest.pointee.height)))
    ctx.flush()
    return kvImageNoError
}

private func eachPixel(_ buffer: vImage_Buffer, _ body: (UnsafeMutablePointer<UInt8>) -> Void) {
    for y in 0..<Int(buffer.height) {
        let row = buffer.data.advanced(by: y * buffer.rowBytes).assumingMemoryBound(to: UInt8.self)
        for x in 0..<Int(buffer.width) { body(row + x * 4) }
    }
}

public func vImageUnpremultiplyData_RGBA8888(_ src: UnsafePointer<vImage_Buffer>, _ dest: UnsafePointer<vImage_Buffer>,
                                             _ flags: vImage_Flags) -> vImage_Error {
    copyIfNeeded(src, dest)
    eachPixel(dest.pointee) { p in
        let a = Int(p[3])
        guard a > 0, a < 255 else { return }
        for c in 0..<3 { p[c] = UInt8(min(255, (Int(p[c]) * 255 + a / 2) / a)) }
    }
    return kvImageNoError
}

public func vImagePremultiplyData_RGBA8888(_ src: UnsafePointer<vImage_Buffer>, _ dest: UnsafePointer<vImage_Buffer>,
                                           _ flags: vImage_Flags) -> vImage_Error {
    copyIfNeeded(src, dest)
    eachPixel(dest.pointee) { p in
        let a = Int(p[3])
        for c in 0..<3 { p[c] = UInt8((Int(p[c]) * a + 127) / 255) }
    }
    return kvImageNoError
}

private func copyIfNeeded(_ src: UnsafePointer<vImage_Buffer>, _ dest: UnsafePointer<vImage_Buffer>) {
    guard src.pointee.data != dest.pointee.data else { return }
    for y in 0..<Int(src.pointee.height) {
        memcpy(dest.pointee.data + y * dest.pointee.rowBytes, src.pointee.data + y * src.pointee.rowBytes,
               Int(src.pointee.width) * 4)
    }
}

public func vImageConvert_ARGB8888toPlanar8(_ src: UnsafePointer<vImage_Buffer>, _ a: UnsafePointer<vImage_Buffer>,
                                            _ r: UnsafePointer<vImage_Buffer>, _ g: UnsafePointer<vImage_Buffer>,
                                            _ b: UnsafePointer<vImage_Buffer>, _ flags: vImage_Flags) -> vImage_Error {
    let planes = [a.pointee, r.pointee, g.pointee, b.pointee]
    let s = src.pointee
    for y in 0..<Int(s.height) {
        let row = s.data.advanced(by: y * s.rowBytes).assumingMemoryBound(to: UInt8.self)
        for (index, plane) in planes.enumerated() {
            let out = plane.data.advanced(by: y * plane.rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in 0..<Int(s.width) { out[x] = row[x * 4 + index] }
        }
    }
    return kvImageNoError
}

public func vImageConvert_Planar8toARGB8888(_ a: UnsafePointer<vImage_Buffer>, _ r: UnsafePointer<vImage_Buffer>,
                                            _ g: UnsafePointer<vImage_Buffer>, _ b: UnsafePointer<vImage_Buffer>,
                                            _ dest: UnsafePointer<vImage_Buffer>, _ flags: vImage_Flags) -> vImage_Error {
    let planes = [a.pointee, r.pointee, g.pointee, b.pointee]
    let d = dest.pointee
    for y in 0..<Int(d.height) {
        let row = d.data.advanced(by: y * d.rowBytes).assumingMemoryBound(to: UInt8.self)
        for (index, plane) in planes.enumerated() {
            let input = plane.data.advanced(by: y * plane.rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in 0..<Int(d.width) { row[x * 4 + index] = input[x] }
        }
    }
    return kvImageNoError
}

/// Shared convolution walk: edge-extended or background-filled samples outside the image.
/// `load`/`store` read and write one sample of a row (8-bit or float planes).
private func convolve(_ src: vImage_Buffer, _ dest: vImage_Buffer, kernelHeight: UInt32, kernelWidth: UInt32,
                      edgeExtend: Bool, background: Double, weight: (Int) -> Double,
                      load: (UnsafeMutableRawPointer, Int) -> Double,
                      store: (UnsafeMutableRawPointer, Int, Double) -> Void) {
    let width = Int(src.width), height = Int(src.height)
    let kw = Int(kernelWidth), kh = Int(kernelHeight)
    for y in 0..<height {
        let out = dest.data.advanced(by: y * dest.rowBytes)
        for x in 0..<width {
            var sum = 0.0
            for j in 0..<kh {
                for i in 0..<kw {
                    var sx = x + i - kw / 2, sy = y + j - kh / 2
                    if sx < 0 || sy < 0 || sx >= width || sy >= height {
                        guard edgeExtend else { sum += weight(j * kw + i) * background; continue }
                        sx = min(max(sx, 0), width - 1)
                        sy = min(max(sy, 0), height - 1)
                    }
                    sum += weight(j * kw + i) * load(src.data.advanced(by: sy * src.rowBytes), sx)
                }
            }
            store(out, x, sum)
        }
    }
}

public func vImageConvolve_Planar8(_ src: UnsafePointer<vImage_Buffer>, _ dest: UnsafePointer<vImage_Buffer>,
                                   _ temp: UnsafeMutableRawPointer?, _ srcOffsetToROI_X: vImagePixelCount,
                                   _ srcOffsetToROI_Y: vImagePixelCount, _ kernel: UnsafePointer<Int16>,
                                   _ kernelHeight: UInt32, _ kernelWidth: UInt32, _ divisor: Int32,
                                   _ backgroundColor: UInt8, _ flags: vImage_Flags) -> vImage_Error {
    let d = Double(divisor == 0 ? 1 : divisor)
    convolve(src.pointee, dest.pointee, kernelHeight: kernelHeight, kernelWidth: kernelWidth,
             edgeExtend: flags & kvImageEdgeExtend != 0, background: Double(backgroundColor),
             weight: { Double(kernel[$0]) },
             load: { Double($0.assumingMemoryBound(to: UInt8.self)[$1]) },
             store: { $0.assumingMemoryBound(to: UInt8.self)[$1] = UInt8(clamping: Int(($2 / d).rounded())) })
    return kvImageNoError
}

public func vImageConvolve_PlanarF(_ src: UnsafePointer<vImage_Buffer>, _ dest: UnsafePointer<vImage_Buffer>,
                                   _ temp: UnsafeMutableRawPointer?, _ srcOffsetToROI_X: vImagePixelCount,
                                   _ srcOffsetToROI_Y: vImagePixelCount, _ kernel: UnsafePointer<Float>,
                                   _ kernelHeight: UInt32, _ kernelWidth: UInt32, _ backgroundColor: Float,
                                   _ flags: vImage_Flags) -> vImage_Error {
    convolve(src.pointee, dest.pointee, kernelHeight: kernelHeight, kernelWidth: kernelWidth,
             edgeExtend: flags & kvImageEdgeExtend != 0, background: Double(backgroundColor),
             weight: { Double(kernel[$0]) },
             load: { Double($0.assumingMemoryBound(to: Float.self)[$1]) },
             store: { $0.assumingMemoryBound(to: Float.self)[$1] = Float($2) })
    return kvImageNoError
}

/// dest[i] = table[src[i]] over an 8-bit plane.
public func vImageTableLookUp_Planar8(_ src: UnsafePointer<vImage_Buffer>, _ dest: UnsafePointer<vImage_Buffer>,
                                      _ table: UnsafePointer<UInt8>, _ flags: vImage_Flags) -> vImage_Error {
    let s = src.pointee, d = dest.pointee
    for y in 0..<Int(s.height) {
        let input = s.data.advanced(by: y * s.rowBytes).assumingMemoryBound(to: UInt8.self)
        let output = d.data.advanced(by: y * d.rowBytes).assumingMemoryBound(to: UInt8.self)
        for x in 0..<Int(s.width) { output[x] = table[Int(input[x])] }
    }
    return kvImageNoError
}

/// C[i] = Float(A[i]) for 8-bit unsigned input.
public func vDSP_vfltu8(_ a: UnsafePointer<UInt8>, _ ia: vDSP_Stride, _ c: UnsafeMutablePointer<Float>,
                        _ ic: vDSP_Stride, _ n: vDSP_Length) {
    for i in 0..<Int(n) { c[i * ic] = Float(a[i * ia]) }
}

public let kvImageDoNotTile: UInt32 = 16

/// Per-channel lookup over a 32-bit buffer; the tables go in memory order (nil leaves a channel).
public func vImageTableLookUp_ARGB8888(_ src: UnsafePointer<vImage_Buffer>, _ dest: UnsafePointer<vImage_Buffer>,
                                       _ alphaTable: UnsafePointer<UInt8>?, _ redTable: UnsafePointer<UInt8>?,
                                       _ greenTable: UnsafePointer<UInt8>?, _ blueTable: UnsafePointer<UInt8>?,
                                       _ flags: vImage_Flags) -> vImage_Error {
    let tables = [alphaTable, redTable, greenTable, blueTable]
    let s = src.pointee, d = dest.pointee
    for y in 0..<Int(s.height) {
        let input = s.data.advanced(by: y * s.rowBytes).assumingMemoryBound(to: UInt8.self)
        let output = d.data.advanced(by: y * d.rowBytes).assumingMemoryBound(to: UInt8.self)
        for x in 0..<Int(s.width) {
            for channel in 0..<4 {
                let value = input[x * 4 + channel]
                output[x * 4 + channel] = tables[channel].map { $0[Int(value)] } ?? value
            }
        }
    }
    return kvImageNoError
}
