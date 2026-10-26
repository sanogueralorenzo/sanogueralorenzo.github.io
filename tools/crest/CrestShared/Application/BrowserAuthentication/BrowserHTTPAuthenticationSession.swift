@MainActor
final class BrowserHTTPAuthenticationSession {
    typealias Prompt = @MainActor (BrowserHTTPAuthenticationPrompt) async -> BrowserHTTPAuthenticationPromptResponse?

    func response(to challenge: BrowserAuthenticationChallenge, prompt: Prompt) async
        -> BrowserHTTPAuthenticationDecision
    {
        await challenge.handling.respond(on: self)(challenge, prompt)
    }
}

extension BrowserHTTPAuthenticationSession: AuthenticationResponder {
    typealias Response = @MainActor (BrowserAuthenticationChallenge, Prompt) async -> BrowserHTTPAuthenticationDecision

    func performDefaultHandling() -> Response { { _, _ in .performDefaultHandling } }
    func cancelChallenge() -> Response { { _, _ in .cancel } }
    func promptForCredentials() -> Response {
        { challenge, prompt in
            guard
                let answer = await prompt(
                    BrowserHTTPAuthenticationPrompt(
                        descriptor: challenge.descriptor, suggestedUsername: challenge.proposedUsername))
            else { return .cancel }
            return .useCredential(username: answer.username, password: answer.password)
        }
    }
}
