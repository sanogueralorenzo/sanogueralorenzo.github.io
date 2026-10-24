import Foundation
import ImageIO

enum BrowserFaviconImageDecoder {
    static let maximumPixelSizeLimit = 512

    static func decode(_ data: Data, maximumPixelSize: Int) async -> CGImage? {
        await BrowserFaviconImageCache.shared.image(
            for: data,
            maximumPixelSize: min(
                max(1, maximumPixelSize),
                maximumPixelSizeLimit
            )
        )
    }

    nonisolated static func decodeSynchronously(
        _ data: Data,
        maximumPixelSize: Int
    ) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(
                max(1, maximumPixelSize),
                maximumPixelSizeLimit
            ),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
