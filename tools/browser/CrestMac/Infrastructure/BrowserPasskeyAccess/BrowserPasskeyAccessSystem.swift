import Foundation
import Security

@MainActor
enum BrowserPasskeyAccessSystem {
    nonisolated private static let managedEntitlement =
        "com.apple.developer.web-browser.public-key-credential"

    nonisolated static func hasManagedCapability() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil),
            let value = SecTaskCopyValueForEntitlement(
                task,
                managedEntitlement as CFString,
                nil
            )
        else {
            return false
        }
        return value as? Bool == true
    }

    nonisolated static func deviceConfiguration() -> PasskeyDeviceConfiguration {
        BrowserPasskeyAuthorizationSystem.deviceConfiguration()
    }

    nonisolated static func authorizationState() -> PasskeyAuthorizationState {
        BrowserPasskeyAuthorizationSystem.authorizationState()
    }

    static func requestAuthorization() async -> PasskeyAuthorizationState {
        await BrowserPasskeyAuthorizationSystem.requestAuthorization()
    }
}
