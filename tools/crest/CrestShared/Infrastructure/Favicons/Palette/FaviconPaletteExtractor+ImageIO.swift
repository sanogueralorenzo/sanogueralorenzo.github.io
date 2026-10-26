import CoreGraphics
import Foundation
import ImageIO

extension BrowserFaviconPaletteExtractor {
    func palette(imageData: Data) -> BrowserFaviconPalette? {
        guard
            let source = CGImageSourceCreateWithData(
                imageData as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary
            )
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: DecodingMetrics.maximumSampleDimension,
        ]
        guard
            let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                options as CFDictionary
            )
        else { return nil }

        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        unpremultiply(&pixels)
        return palette(rgbaPixels: pixels, width: width, height: height)
    }

    private enum DecodingMetrics {
        static let maximumSampleDimension = 64
    }

    private func unpremultiply(_ pixels: inout [UInt8]) {
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[offset + 3])
            guard alpha > 0, alpha < 255 else { continue }
            pixels[offset] = UInt8(min(255, (Int(pixels[offset]) * 255) / alpha))
            pixels[offset + 1] = UInt8(min(255, (Int(pixels[offset + 1]) * 255) / alpha))
            pixels[offset + 2] = UInt8(min(255, (Int(pixels[offset + 2]) * 255) / alpha))
        }
    }
}
