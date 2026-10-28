import Foundation
import ImageIO

actor BrowserFaviconImageCache {
    static let shared = BrowserFaviconImageCache()
    static let maximumCachedImageCount = 256

    private let decode: @Sendable (Data, Int) -> CGImage?
    private var images: [BrowserFaviconImageCacheKey: CGImage] = [:]
    private var recency: [BrowserFaviconImageCacheKey] = []
    private var requests = BrowserFaviconImageCacheRequestRegistry()

    init(
        decode: @escaping @Sendable (Data, Int) -> CGImage? =
            BrowserFaviconImageDecoder.decodeSynchronously
    ) {
        self.decode = decode
    }

    func image(for data: Data, maximumPixelSize: Int) async -> CGImage? {
        // Fingerprinting here, on the cache's own executor rather than the main
        // actor, is what lets two tabs that show the same icon share one decode.
        let key = BrowserFaviconImageCacheKey(
            payload: BrowserFaviconPayloadIdentity(hashing: data),
            maximumPixelSize: maximumPixelSize
        )
        if let image = images[key] {
            recordAccess(to: key)
            return image
        }

        let lease = requests.lease(for: key) {
            let decode = decode
            return Task.detached(priority: .utility) {
                decode(data, maximumPixelSize)
            }
        }

        let decodedImage = await lease.task.value
        guard requests.isCurrent(lease) else { return nil }
        guard requests.complete(lease, for: key) else { return images[key] }
        guard let decodedImage else { return nil }
        insert(decodedImage, for: key)
        return decodedImage
    }

    func removeAll() {
        images.removeAll(keepingCapacity: true)
        recency.removeAll(keepingCapacity: true)
        for lease in requests.removeAll() {
            lease.task.cancel()
        }
    }

    private func insert(_ image: CGImage, for key: BrowserFaviconImageCacheKey) {
        images[key] = image
        recordAccess(to: key)
        while images.count > Self.maximumCachedImageCount,
            let leastRecent = recency.first
        {
            recency.removeFirst()
            images[leastRecent] = nil
        }
    }

    private func recordAccess(to key: BrowserFaviconImageCacheKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}
