import Foundation

extension BrowserAuthenticationChallenge {
    // MARK: - Variables

    /// How the core answers this challenge. An unavailable core cancels it
    /// rather than prompting or handing over stored credentials.
    var handling: AuthenticationHandling {
        ChallengeHandling(
            method: authenticationMethod, isProxy: isProxy, previousFailureCount: previousFailureCount
        ).handling
    }
}
