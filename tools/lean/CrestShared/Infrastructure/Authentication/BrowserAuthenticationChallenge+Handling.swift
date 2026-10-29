import Foundation

extension BrowserAuthenticationChallenge {
    // MARK: - Variables

    /// Basic and Digest prompt; proxy and other challenges keep system handling.
    var handling: AuthenticationHandling {
        AuthenticationHandling.handling(
            method: authenticationMethod, isProxy: isProxy, previousFailureCount: previousFailureCount
        )
    }
}
