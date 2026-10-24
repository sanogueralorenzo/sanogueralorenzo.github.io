import Foundation

/// The document posts a notification.
struct BrowserHostedNotificationCreation: BrowserHostedNotificationMessage {
    // MARK: - Static Variables

    static let action = "create"

    // MARK: - Variables

    let identifier: String
    let title: String
    let body: String
    let isSilent: Bool

    // MARK: - Initializers

    init?(body: [String: Any]) {
        guard let identifier = body["identifier"] as? String,
            Self.isValid(identifier),
            let title = body["title"] as? String,
            let notificationBody = body["body"] as? String
        else { return nil }
        self.identifier = identifier
        self.title = title
        self.body = notificationBody
        isSilent = body["silent"] as? Bool ?? false
    }

    // MARK: - Actions - Notifications

    func handle(on page: BrowserPage, in document: BrowserHostedNotificationDocument) {
        Task { @MainActor [weak page] in
            await page?.createHostedWebNotification(
                identifier: identifier,
                title: title,
                body: body,
                isSilent: isSilent,
                origin: document.origin,
                documentIdentifier: document.identifier
            )
        }
    }
}
