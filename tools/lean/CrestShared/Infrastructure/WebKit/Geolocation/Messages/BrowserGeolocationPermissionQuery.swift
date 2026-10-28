import Foundation

/// The frame asks which location permission it has.
struct BrowserGeolocationPermissionQuery: BrowserGeolocationMessage {
    // MARK: - Initializers

    init?(action: String, body: [String: Any]) {
        guard action == "queryPermission" else { return nil }
    }

    // MARK: - Actions - Geolocation

    func handle(on coordinator: BrowserGeolocationCoordinator, in frame: BrowserGeolocationFrame) {
        coordinator.sendPermission(
            origin: frame.origin,
            documentIdentifier: frame.documentIdentifier,
            frame: frame.frame,
            frameDocumentIdentifier: frame.frameDocumentIdentifier
        )
    }
}
