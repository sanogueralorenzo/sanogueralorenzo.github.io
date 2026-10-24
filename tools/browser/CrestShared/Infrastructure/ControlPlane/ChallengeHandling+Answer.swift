import Foundation

/// HTTP authentication rules answered by the portable core. No username or
/// password crosses: a challenge is its method, proxy flag and failure count.
extension ChallengeHandling {
    // MARK: - Variables

    /// How the challenge is answered. An unavailable core cancels the
    /// challenge rather than prompting or handing over stored credentials.
    var handling: AuthenticationHandling {
        (try? CrestCore.answer(self))?.handling ?? .cancel
    }
}
