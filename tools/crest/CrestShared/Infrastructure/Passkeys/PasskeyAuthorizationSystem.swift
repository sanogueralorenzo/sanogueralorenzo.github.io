import AuthenticationServices

@MainActor
enum BrowserPasskeyAuthorizationSystem {
    nonisolated static func deviceConfiguration() -> PasskeyDeviceConfiguration {
        if #available(macOS 26.2, iOS 26.2, *) {
            return ASAuthorizationWebBrowserPublicKeyCredentialManager
                .isDeviceConfiguredForPasskeys ? .configured : .notConfigured
        }
        return .unknown
    }

    nonisolated static func authorizationState() -> PasskeyAuthorizationState {
        PasskeyAuthorizationState(
            ASAuthorizationWebBrowserPublicKeyCredentialManager()
                .authorizationStateForPlatformCredentials
        )
    }

    static func requestAuthorization() async -> PasskeyAuthorizationState {
        let manager = ASAuthorizationWebBrowserPublicKeyCredentialManager()
        return await withCheckedContinuation { continuation in
            manager.requestAuthorizationForPublicKeyCredentials { state in
                continuation.resume(
                    returning: PasskeyAuthorizationState(state)
                )
            }
        }
    }
}
