import Foundation

extension BrowserHTTPAuthenticationSession {
    func response(
        to challenge: URLAuthenticationChallenge,
        prompt: Prompt
    ) async -> BrowserHTTPAuthenticationResolution {
        let decision = await response(
            to: BrowserAuthenticationChallenge(challenge),
            prompt: prompt
        )
        return BrowserHTTPAuthenticationResolution(decision)
    }
}
