import CoreGraphics
import Foundation

enum BrowserFaviconRenderLoader {
    static func decode(
        _ request: BrowserFaviconRenderRequest,
        fallbackData: @escaping @Sendable (URL, UUID) async -> Data? = {
            pageURL,
            profileID in
            await BrowserFaviconFallbackLoader.shared.data(
                for: pageURL,
                profileID: profileID
            )
        }
    ) async -> CGImage? {
        var data = request.payload
        if data == nil,
            let pageURL = request.fallbackPageURL,
            let profileID = request.fallbackProfileID
        {
            data = await fallbackData(pageURL, profileID)
        }
        guard !Task.isCancelled, let data else { return nil }
        let image = await BrowserFaviconImageDecoder.decode(
            data,
            maximumPixelSize: request.identity.maximumPixelSize
        )
        guard !Task.isCancelled else { return nil }
        return image
    }
}
