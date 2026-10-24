import Foundation

struct BrowserGeolocationRequestOptions: Equatable, Sendable {
    let enablesHighAccuracy: Bool
    let maximumAge: TimeInterval

    init(enablesHighAccuracy: Bool, maximumAge: TimeInterval) {
        self.enablesHighAccuracy = enablesHighAccuracy
        self.maximumAge = max(maximumAge, 0)
    }
}

struct BrowserGeolocationPosition: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let altitude: Double?
    let altitudeAccuracy: Double?
    let heading: Double?
    let speed: Double?
    let timestamp: TimeInterval
}

struct BrowserGeolocationError: Error, Equatable, Sendable {
    enum Code: Int, Equatable, Sendable {
        case permissionDenied = 1
        case positionUnavailable = 2
        case timeout = 3
    }

    let code: Code
    let message: String

    static let permissionDenied = BrowserGeolocationError(
        code: .permissionDenied,
        message: "Location permission was denied."
    )

    static let positionUnavailable = BrowserGeolocationError(
        code: .positionUnavailable,
        message: "The current location is unavailable."
    )
}
