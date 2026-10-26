import AVFoundation
import AppKit
import CoreLocation
import UserNotifications

@MainActor
final class BrowserSystemPermissionService: BrowserSystemPermissionServicing {
    private let location = BrowserGeolocationSystemService()
    let folderAccess = BrowserSystemFolderAccess()
    let passkeyAccess: BrowserPasskeyAccessController
    private let readPasskeyStatus: @Sendable () -> PasskeyAccessStatus

    /// `passkeyAccess` is the app's one passkey controller, which a request
    /// updates. `readPasskeyStatus` runs off the main actor; without one, the
    /// service reads the system's passkey facts and asks `core` for the status.
    init(
        core: CrestCore, passkeyAccess: BrowserPasskeyAccessController,
        readPasskeyStatus: (@Sendable () -> PasskeyAccessStatus)? = nil
    ) {
        self.passkeyAccess = passkeyAccess
        self.readPasskeyStatus = readPasskeyStatus ?? { Self.passkeyStatus(asking: core) }
    }

    func status(for permission: BrowserSystemPermission, spaceID: UUID?) async -> BrowserSystemPermissionStatus {
        await permission.status(self, spaceID)
    }

    func request(_ permission: BrowserSystemPermission, spaceID: UUID?) async throws {
        try await permission.request(self, spaceID)
    }

    func chooseFolder(spaceID: UUID) async throws {
        try await folderAccess.chooseFolder(spaceID: spaceID)
    }

    func openSettings(for permission: BrowserSystemPermission) -> Bool {
        guard let url = permission.settingsURL else { return false }
        return NSWorkspace.shared.open(url)
    }

    func locationStatus() async -> BrowserSystemPermissionStatus {
        let enabled = await Task.detached { CLLocationManager.locationServicesEnabled() }.value
        guard enabled else {
            return .init(
                state: .blocked,
                detail: String(localized: "Turn on Location Services for this Mac, then allow Crest."))
        }
        switch CLLocationManager().authorizationStatus {
        case .notDetermined: return .init(state: .notRequested)
        case .authorizedAlways, .authorizedWhenInUse: return .init(state: .allowed)
        case .denied: return .init(state: .blocked)
        case .restricted: return .init(state: .restricted)
        @unknown default: return .init(state: .unavailable)
        }
    }

    func requestLocation() async throws {
        guard await location.requestAuthorization() == .notDetermined else { return }
        throw NSError(
            domain: "BrowserSystemPermission", code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: String(
                    localized:
                        "macOS has not returned a location decision. Respond to its prompt, or open System Settings > Privacy & Security > Location Services to allow Crest."
                )
            ])
    }

    func notificationStatus() async -> BrowserSystemPermissionStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .init(state: .notRequested)
        case .denied: return .init(state: .blocked)
        case .authorized, .provisional, .ephemeral:
            return .init(
                state: .allowed,
                detail: settings.alertSetting == .disabled
                    ? String(localized: "Notifications are allowed, but banners are off in System Settings.") : nil)
        @unknown default: return .init(state: .unavailable)
        }
    }

    func passkeyStatus() async -> BrowserSystemPermissionStatus {
        let readPasskeyStatus = readPasskeyStatus
        // These read-only APIs can wait for synchronous system IPC.
        // Keep that wait away from the UI while General settings opens.
        let status = await Task.detached(priority: .userInitiated) { readPasskeyStatus() }.value
        let detail = status.settingsDetail.map { String(localized: $0) }
        return .init(state: Self.permissionState(for: status), detail: detail)
    }

    /// The system permissions row's state for the core's passkey status.
    nonisolated private static func permissionState(for status: PasskeyAccessStatus) -> BrowserSystemPermissionState {
        if status.isChecking { return .checking }
        if status.isReady { return .allowed }
        if status.needsAttention { return .blocked }
        return status.canRequestAccess ? .notRequested : .unavailable
    }

    /// The system's passkey facts and the core's status for them. A core that
    /// cannot answer keeps checking.
    nonisolated private static func passkeyStatus(asking core: CrestCore) -> PasskeyAccessStatus {
        guard BrowserPasskeyAccessSystem.hasManagedCapability() else { return .managedCapabilityRequired }
        let access = PasskeyAccess(
            hasManagedCapability: true, deviceConfiguration: BrowserPasskeyAccessSystem.deviceConfiguration(),
            authorizationState: BrowserPasskeyAccessSystem.authorizationState())
        return (try? core.query(access))?.status ?? .checking
    }

    func captureStatus(_ type: AVMediaType) async -> BrowserSystemPermissionStatus {
        let status = await Task.detached(priority: .userInitiated) {
            AVCaptureDevice.authorizationStatus(for: type)
        }.value
        return switch status {
        case .authorized: .init(state: .allowed)
        case .notDetermined: .init(state: .notRequested)
        case .denied: .init(state: .blocked)
        case .restricted: .init(state: .restricted)
        @unknown default: .init(state: .unavailable)
        }
    }
}
