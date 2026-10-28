import Foundation

/// Answers a server's request for a user name and password the way the
/// core's rules handle it: one method per handling, each giving back what
/// the one who asked expects. A handling the core adds fails to compile
/// until every responder takes it.
@MainActor
protocol AuthenticationResponder {
    /// What answering gives back to whoever asked.
    associatedtype Response

    func performDefaultHandling() -> Response
    func cancelChallenge() -> Response
    func promptForCredentials() -> Response
}
