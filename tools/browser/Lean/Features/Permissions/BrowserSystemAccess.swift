import AVFoundation
import AppKit
import AuthenticationServices
import CoreLocation
import Security
import UserNotifications

@MainActor enum BrowserSystemAccess {
    static var passkeyState: String {
        let status = ASAuthorizationWebBrowserPublicKeyCredentialManager().authorizationStateForPlatformCredentials
        switch status {
        case .authorized: return "Authorized"
        case .denied: return "Denied in System Settings"
        case .notDetermined: return "Not Authorized"
        @unknown default: return "Unavailable"
        }
    }
    static func requestPasskeys() async {
        let manager = ASAuthorizationWebBrowserPublicKeyCredentialManager()
        await withCheckedContinuation { continuation in
            manager.requestAuthorizationForPublicKeyCredentials { _ in continuation.resume() }
        }
    }
    static var passkeyCapability: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
            let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.developer.web-browser.public-key-credential" as CFString, nil)
        else { return false }
        return value as? Bool == true
    }
    static func settings(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:" + pane) else { return }
        NSWorkspace.shared.open(url)
    }
}
