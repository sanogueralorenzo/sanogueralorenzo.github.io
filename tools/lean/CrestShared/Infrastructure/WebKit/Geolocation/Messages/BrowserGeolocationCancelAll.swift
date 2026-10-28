import Foundation

/// The frame cancels every request it made.
struct BrowserGeolocationCancelAll: BrowserGeolocationMessage {
    // MARK: - Initializers

    init?(action: String, body: [String: Any]) {
        guard action == "cancelAll" else { return nil }
    }

    // MARK: - Actions - Geolocation

    func handle(on coordinator: BrowserGeolocationCoordinator, in frame: BrowserGeolocationFrame) {
        coordinator.cancelRequests(of: frame.origin, inFrameDocument: frame.frameDocumentIdentifier)
    }
}
