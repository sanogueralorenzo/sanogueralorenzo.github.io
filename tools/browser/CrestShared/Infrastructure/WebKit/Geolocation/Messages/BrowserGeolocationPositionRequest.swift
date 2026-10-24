import Foundation

/// The frame asks for the person's position once, or to watch it.
struct BrowserGeolocationPositionRequest: BrowserGeolocationMessage {
    // MARK: - Static Variables

    /// Each action this message answers, with whether it watches the position.
    private static let watchesPositionByAction = ["getCurrentPosition": false, "watchPosition": true]

    // MARK: - Variables

    let identifier: String
    let watchesPosition: Bool
    let options: BrowserGeolocationRequestOptions

    // MARK: - Initializers

    init?(action: String, body: [String: Any]) {
        guard let watchesPosition = Self.watchesPositionByAction[action],
            let identifier = body["identifier"] as? String,
            Self.isValid(identifier)
        else { return nil }
        self.identifier = identifier
        self.watchesPosition = watchesPosition
        let options = body["options"] as? [String: Any]
        let maximumAgeMilliseconds = options?["maximumAge"] as? Double ?? 0
        self.options = BrowserGeolocationRequestOptions(
            enablesHighAccuracy: options?["enableHighAccuracy"] as? Bool ?? false,
            maximumAge: maximumAgeMilliseconds / 1_000
        )
    }

    // MARK: - Actions - Geolocation

    func handle(on coordinator: BrowserGeolocationCoordinator, in frame: BrowserGeolocationFrame) {
        coordinator.beginRequest(
            identifier: identifier,
            watchesPosition: watchesPosition,
            options: options,
            origin: frame.origin,
            documentIdentifier: frame.documentIdentifier,
            frame: frame.frame,
            frameDocumentIdentifier: frame.frameDocumentIdentifier
        )
    }
}
