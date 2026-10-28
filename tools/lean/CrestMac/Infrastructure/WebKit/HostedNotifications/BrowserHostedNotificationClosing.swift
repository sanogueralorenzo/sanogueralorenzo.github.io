import Foundation

/// The document closes a notification it posted.
struct BrowserHostedNotificationClosing: BrowserHostedNotificationMessage {
    // MARK: - Static Variables

    static let action = "close"

    // MARK: - Variables

    let identifier: String

    // MARK: - Initializers

    init?(body: [String: Any]) {
        guard let identifier = body["identifier"] as? String, Self.isValid(identifier) else { return nil }
        self.identifier = identifier
    }

    // MARK: - Actions - Notifications

    func handle(on page: BrowserPage, in document: BrowserHostedNotificationDocument) {
        page.withdrawWebNotification(page.hostedSystemIdentifier(for: identifier))
    }
}
