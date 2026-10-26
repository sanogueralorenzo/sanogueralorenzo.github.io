import Foundation

/// The frame cancels one of its requests.
struct BrowserGeolocationCancellation: BrowserGeolocationMessage {
    // MARK: - Variables

    let identifier: String

    // MARK: - Initializers

    init?(action: String, body: [String: Any]) {
        guard action == "cancel", let identifier = body["identifier"] as? String, Self.isValid(identifier)
        else { return nil }
        self.identifier = identifier
    }

    // MARK: - Actions - Geolocation

    func handle(on coordinator: BrowserGeolocationCoordinator, in frame: BrowserGeolocationFrame) {
        coordinator.cancel(
            nativeIdentifier:
                "\(frame.documentIdentifier).\(frame.origin.displayName).\(frame.frameDocumentIdentifier).\(identifier)"
        )
    }
}
