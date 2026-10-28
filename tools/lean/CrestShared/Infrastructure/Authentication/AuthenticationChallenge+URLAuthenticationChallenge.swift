import Foundation

extension BrowserAuthenticationChallenge {
    init(_ challenge: URLAuthenticationChallenge) {
        let protectionSpace = challenge.protectionSpace
        self.init(
            authenticationMethod: AuthenticationMethod(
                authenticationMethod: protectionSpace.authenticationMethod
            ),
            isProxy: protectionSpace.isProxy(),
            previousFailureCount: challenge.previousFailureCount,
            descriptor: BrowserHTTPAuthenticationDescriptor(challenge: challenge),
            proposedUsername: challenge.proposedCredential?.user
        )
    }
}
