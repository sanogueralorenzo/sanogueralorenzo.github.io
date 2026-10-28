import CoreLocation
import Foundation

@MainActor
final class BrowserGeolocationSystemService: NSObject, BrowserGeolocationServicing {
    private struct Registration {
        let options: BrowserGeolocationRequestOptions
        let receive: @MainActor (Result<BrowserGeolocationPosition, BrowserGeolocationError>) -> Void
    }

    private lazy var manager: CLLocationManager = {
        let manager = providedManager ?? CLLocationManager()
        manager.delegate = self
        manager.distanceFilter = kCLDistanceFilterNone
        return manager
    }()
    private let providedManager: CLLocationManager?
    private let authorizationTimeout: Duration
    private var authorizationTimeoutTask: Task<Void, Never>?

    init(manager: CLLocationManager? = nil, authorizationTimeout: Duration = .seconds(30)) {
        self.providedManager = manager
        self.authorizationTimeout = authorizationTimeout
        super.init()
    }

    private var authorizationContinuations: [CheckedContinuation<BrowserSystemAuthorization, Never>] = []
    private var oneShotRegistrations: [String: Registration] = [:]
    private var watchRegistrations: [String: Registration] = [:]
    private var cachedLocation: CLLocation?

    func currentAuthorization() -> BrowserSystemAuthorization {
        return Self.authorization(from: manager.authorizationStatus)
    }

    func requestAuthorization() async -> BrowserSystemAuthorization {
        let authorization = currentAuthorization()
        guard authorization == .notDetermined else { return authorization }
        return await withCheckedContinuation { continuation in
            authorizationContinuations.append(continuation)
            if authorizationContinuations.count == 1 {
                // Core Location can decline to present a prompt without a terminal callback.
                // Finish with the actual status so callers can offer recovery without saving a denial.
                authorizationTimeoutTask = Task { [weak self, authorizationTimeout] in
                    do { try await Task.sleep(for: authorizationTimeout) } catch { return }
                    guard let self else { return }
                    finishAuthorization(with: currentAuthorization())
                }
                manager.requestWhenInUseAuthorization()
            }
        }
    }

    func requestCurrentPosition(
        identifier: String,
        options: BrowserGeolocationRequestOptions,
        receive: @escaping @MainActor (Result<BrowserGeolocationPosition, BrowserGeolocationError>) -> Void
    ) {
        guard currentAuthorization() == .authorized else {
            receive(.failure(.permissionDenied))
            return
        }
        if let cachedLocation,
            options.maximumAge > 0,
            Date().timeIntervalSince(cachedLocation.timestamp) <= options.maximumAge
        {
            receive(.success(Self.position(from: cachedLocation)))
            return
        }
        oneShotRegistrations[identifier] = Registration(
            options: options,
            receive: receive
        )
        updateDesiredAccuracy()
        manager.requestLocation()
    }

    func startWatchingPosition(
        identifier: String,
        options: BrowserGeolocationRequestOptions,
        receive: @escaping @MainActor (Result<BrowserGeolocationPosition, BrowserGeolocationError>) -> Void
    ) {
        guard currentAuthorization() == .authorized else {
            receive(.failure(.permissionDenied))
            return
        }
        watchRegistrations[identifier] = Registration(
            options: options,
            receive: receive
        )
        updateDesiredAccuracy()
        if let cachedLocation,
            options.maximumAge > 0,
            Date().timeIntervalSince(cachedLocation.timestamp) <= options.maximumAge
        {
            receive(.success(Self.position(from: cachedLocation)))
        }
        manager.startUpdatingLocation()
    }

    func cancel(identifier: String) {
        oneShotRegistrations.removeValue(forKey: identifier)
        watchRegistrations.removeValue(forKey: identifier)
        updateManagerActivity()
    }

    func cancelAll() {
        oneShotRegistrations.removeAll()
        watchRegistrations.removeAll()
        manager.stopUpdatingLocation()
    }

    private func updateDesiredAccuracy() {
        let needsHighAccuracy =
            oneShotRegistrations.values.contains(where: {
                $0.options.enablesHighAccuracy
            })
            || watchRegistrations.values.contains(where: {
                $0.options.enablesHighAccuracy
            })
        manager.desiredAccuracy =
            needsHighAccuracy
            ? kCLLocationAccuracyBest
            : kCLLocationAccuracyHundredMeters
    }

    private func updateManagerActivity() {
        updateDesiredAccuracy()
        if watchRegistrations.isEmpty {
            manager.stopUpdatingLocation()
        }
    }

    private func receiveAuthorizationChange() {
        let authorization = currentAuthorization()
        if authorization != .notDetermined {
            finishAuthorization(with: authorization)
        }
        if authorization == .denied {
            failAll(with: .permissionDenied)
        }
    }

    private func finishAuthorization(with authorization: BrowserSystemAuthorization) {
        authorizationTimeoutTask?.cancel()
        authorizationTimeoutTask = nil
        let continuations = authorizationContinuations
        authorizationContinuations.removeAll()
        for continuation in continuations {
            continuation.resume(returning: authorization)
        }
    }

    private func failAll(with error: BrowserGeolocationError) {
        let registrations =
            Array(oneShotRegistrations.values)
            + Array(watchRegistrations.values)
        oneShotRegistrations.removeAll()
        watchRegistrations.removeAll()
        manager.stopUpdatingLocation()
        for registration in registrations {
            registration.receive(.failure(error))
        }
    }

    private static func authorization(
        from status: CLAuthorizationStatus
    ) -> BrowserSystemAuthorization {
        switch status {
        case .notDetermined:
            .notDetermined
        case .restricted, .denied:
            .denied
        case .authorizedAlways, .authorizedWhenInUse:
            .authorized
        @unknown default:
            .denied
        }
    }

    private static func position(from location: CLLocation) -> BrowserGeolocationPosition {
        BrowserGeolocationPosition(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracy: max(location.horizontalAccuracy, 0),
            altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
            altitudeAccuracy: location.verticalAccuracy >= 0
                ? location.verticalAccuracy : nil,
            heading: location.course >= 0 ? location.course : nil,
            speed: location.speed >= 0 ? location.speed : nil,
            timestamp: location.timestamp.timeIntervalSince1970 * 1_000
        )
    }
}

extension BrowserGeolocationSystemService: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        receiveAuthorizationChange()
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else {
            return
        }
        cachedLocation = location
        let position = Self.position(from: location)
        let oneShots = Array(oneShotRegistrations.values)
        oneShotRegistrations.removeAll()
        for registration in oneShots {
            registration.receive(.success(position))
        }
        for registration in watchRegistrations.values {
            registration.receive(.success(position))
        }
        updateManagerActivity()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let locationError = error as? CLError
        let browserError: BrowserGeolocationError =
            locationError?.code == .denied
            ? .permissionDenied
            : .positionUnavailable
        if locationError?.code == .denied {
            failAll(with: browserError)
            return
        }
        let oneShots = Array(oneShotRegistrations.values)
        oneShotRegistrations.removeAll()
        for registration in oneShots {
            registration.receive(.failure(browserError))
        }
        for registration in watchRegistrations.values {
            registration.receive(.failure(browserError))
        }
        updateManagerActivity()
    }
}
