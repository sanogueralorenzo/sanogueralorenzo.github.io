import Foundation
import WebKit

// MARK: - Types

/// The document a hosted notification message came from: its identity on
/// the page, its origin and the frame that sent it.
struct BrowserHostedNotificationDocument {
    let identifier: String
    let origin: SiteOrigin
    let frame: WKFrameInfo
}

/// A message the page's notification bridge sends, decoded once from its
/// body. Each message names its bridge action and handles itself on the
/// page, so the bridge's receiver only decodes it.
@MainActor
protocol BrowserHostedNotificationMessage {
    /// The bridge's name for the message.
    static var action: String { get }

    /// The message `body` carries, or nil when it is malformed.
    init?(body: [String: Any])

    func handle(on page: BrowserPage, in document: BrowserHostedNotificationDocument)
}

extension BrowserHostedNotificationMessage {
    /// Whether `identifier`, a request's or a notification's, is one the
    /// bridge accepts.
    static func isValid(_ identifier: String) -> Bool {
        !identifier.isEmpty && identifier.utf8.count <= 128
    }
}
