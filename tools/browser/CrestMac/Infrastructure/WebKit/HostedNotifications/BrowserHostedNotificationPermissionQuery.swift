import Foundation

/// The document asks which notification permission it has.
struct BrowserHostedNotificationPermissionQuery: BrowserHostedNotificationMessage {
    // MARK: - Static Variables

    static let action = "queryPermission"

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
            await page?.sendHostedNotificationPermission(
                requestID: requestID,
                origin: document.origin,
                requestsSystemAuthorization: false,
                documentIdentifier: document.identifier,
                frame: document.frame
            )
        }
    }
}
