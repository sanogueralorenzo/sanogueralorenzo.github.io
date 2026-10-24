import Foundation
import SwiftUI

struct BrowserFaviconRenderRequest: Sendable {
    let identity: BrowserFaviconTaskIdentity
    let payload: Data?
    let fallbackPageURL: URL?
    let fallbackProfileID: UUID?
}

@MainActor
struct BrowserFaviconRenderState {
    private(set) var activeRequestIdentity: BrowserFaviconTaskIdentity?
    private(set) var renderedImage: BrowserFaviconRenderedImage?

    mutating func begin(
        _ requestIdentity: BrowserFaviconTaskIdentity,
        isCancelled: Bool
    ) {
        guard !isCancelled else { return }
        activeRequestIdentity = requestIdentity
    }

    mutating func publish(
        _ image: Image,
        for requestIdentity: BrowserFaviconTaskIdentity,
        isCancelled: Bool
    ) {
        guard !isCancelled,
            activeRequestIdentity == requestIdentity
        else { return }
        renderedImage = BrowserFaviconRenderedImage(
            requestIdentity: requestIdentity,
            image: image
        )
    }
}

struct BrowserFaviconRenderedImage {
    let requestIdentity: BrowserFaviconTaskIdentity
    let image: Image

    func image(matching identity: BrowserFaviconTaskIdentity) -> Image? {
        guard requestIdentity == identity else { return nil }
        return image
    }
}

struct BrowserFaviconTaskIdentity: Hashable, Sendable {
    let tabID: UUID
    let profileID: UUID?
    let pageURL: URL?
    let iconMode: String
    let payload: BrowserFaviconPayloadIdentity?
    let maximumPixelSize: Int
    /// Part of the identity so unlocking a Space restarts the render task that
    /// was deliberately starved of its network fallback while locked.
    var isUnlocked: Bool = true
}
