import Foundation

/// The document calls `Notification.requestPermission()`.
struct BrowserHostedNotificationPermissionRequest: BrowserHostedNotificationMessage {
    // MARK: - Static Variables

    static let action = "requestPermission"

    // MARK: - Variables

    let requestID: String

    // MARK: - Initializers

    init?(body: [String: Any]) {
        guard let requestID = body["requestID"] as? String, Self.isValid(requestID) else { return nil }
        self.requestID = requestID
    }

    // MARK: - Actions - Notifications

    func handle(on page: BrowserPage, in document: BrowserHostedNotificationDocument) {
        Task { @MainActor [weak page] in
            guard let page else { return }
            let userActivation = await page.hasActiveUserGesture(in: document.frame)
            await page.resolveHostedNotificationPermission(
                requestID: requestID,
                origin: document.origin,
                hasUserActivation: userActivation,
                documentIdentifier: document.identifier,
                frame: document.frame
            )
        }
    }
}
