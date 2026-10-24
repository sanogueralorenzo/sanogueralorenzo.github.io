import Foundation
import WebKit

// MARK: - Types

/// The frame a geolocation message came from: its page document, its origin,
/// and its own document's identity in the bridge.
struct BrowserGeolocationFrame {
    let origin: SiteOrigin
    let documentIdentifier: String
    let frame: WKFrameInfo
    let frameDocumentIdentifier: String
}

/// A message the page's geolocation bridge sends, decoded once from its
/// action and body. Each message handles itself on the coordinator, so the
/// bridge's receiver only decodes it.
@MainActor
protocol BrowserGeolocationMessage {
    /// The message `body` carries for the bridge's `action`, or nil when the
    /// action is another message's or the body is malformed.
    init?(action: String, body: [String: Any])

    func handle(on coordinator: BrowserGeolocationCoordinator, in frame: BrowserGeolocationFrame)
}

extension BrowserGeolocationMessage {
    /// Whether `identifier`, a request's, is one the bridge accepts.
    static func isValid(_ identifier: String) -> Bool {
        !identifier.isEmpty && identifier.utf8.count <= 128
    }
}
