import Foundation

@MainActor
enum BrowserPasskeyAccessSystem {
    private static let buildManifestKey =
        "CrestBrowserPasskeyManagedCapability"

    static func hasManagedCapability() -> Bool {
        // iOS does not expose SecTask in its public SDK. This source-controlled
        // manifest remains false until the corresponding managed entitlement is
        // provisioned and added to CrestMobile.entitlements.
        Bundle.main.object(forInfoDictionaryKey: buildManifestKey) as? Bool == true
    }

    static func deviceConfiguration() -> PasskeyDeviceConfiguration {
        BrowserPasskeyAuthorizationSystem.deviceConfiguration()
    }

    static func authorizationState() -> PasskeyAuthorizationState {
        BrowserPasskeyAuthorizationSystem.authorizationState()
    }

    static func requestAuthorization() async -> PasskeyAuthorizationState {
        await BrowserPasskeyAuthorizationSystem.requestAuthorization()
    }
}
