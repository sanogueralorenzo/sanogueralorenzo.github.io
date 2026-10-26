import AuthenticationServices

extension PasskeyAuthorizationState {
    init(
        _ state: ASAuthorizationWebBrowserPublicKeyCredentialManager.AuthorizationState
    ) {
        self =
            switch state {
            case .authorized:
                .authorized
            case .denied:
                .denied
            case .notDetermined:
                .notDetermined
            @unknown default:
                .notDetermined
            }
    }
}
