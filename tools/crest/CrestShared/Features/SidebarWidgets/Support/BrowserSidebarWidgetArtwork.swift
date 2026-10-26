import ImageIO
import SwiftUI

/// Reduces oversized artwork before decoding it for SwiftUI.
enum BrowserSidebarWidgetArtwork {
    // MARK: - Static Variables

    /// Native rendering keeps ordinary source pixels intact. These limits are
    /// only a decode-safety boundary for unusually large compressed images.
    static let maximumPixelDimension = 4_096
    static let maximumPixelCount = 16 * 1_024 * 1_024

    // MARK: - Actions - Decoding

    static func image(from data: Data) -> Image? {
        guard
            let source = CGImageSourceCreateWithData(
                data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ), let properties = properties(for: source)
        else { return nil }
        let pixelCount = properties.width.multipliedReportingOverflow(
            by: properties.height
        )
        let needsSafetyReduction =
            pixelCount.overflow
            || pixelCount.partialValue
                > maximumPixelCount
            || max(properties.width, properties.height)
                > maximumPixelDimension
        if needsSafetyReduction {
            guard
                let image = CGImageSourceCreateThumbnailAtIndex(
                    source,
                    0,
                    [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize:
                            maximumPixelDimension,
                        kCGImageSourceShouldCacheImmediately: true,
                    ] as CFDictionary
                )
            else { return nil }
            return Image(decorative: image, scale: 1, orientation: .up)
        }
        guard
            let image = CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            )
        else { return nil }
        return Image(
            decorative: image,
            scale: 1,
            orientation: properties.orientation
        )
    }

    private static func properties(
        for source: CGImageSource
    ) -> (width: Int, height: Int, orientation: Image.Orientation)? {
        guard
            let values = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
            let width = (values[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            let height = (values[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
            width > 0, height > 0
        else { return nil }
        let rawOrientation =
            (values[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        return (width, height, orientation(rawValue: rawOrientation))
    }

    private static func orientation(rawValue: UInt32) -> Image.Orientation {
        switch rawValue {
        case 2: .upMirrored
        case 3: .down
        case 4: .downMirrored
        case 5: .leftMirrored
        case 6: .right
        case 7: .rightMirrored
        case 8: .left
        default: .up
        }
    }
}
