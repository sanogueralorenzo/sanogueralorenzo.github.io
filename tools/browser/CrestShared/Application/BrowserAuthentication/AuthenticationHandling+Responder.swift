import Foundation

extension AuthenticationHandling {
    /// Answers the challenge on `responder`, by its method for this handling.
    @MainActor func respond<Responder: AuthenticationResponder>(on responder: Responder) -> Responder.Response {
        switch self {
        case .performDefaultHandling: responder.performDefaultHandling()
        case .cancel: responder.cancelChallenge()
        case .promptForCredentials: responder.promptForCredentials()
        }
    }
}
