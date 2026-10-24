import Foundation

/// External scheme, link and local-file rules answered by the portable core.
/// URLs cross as the facts Foundation's parser reports, so the core judges the
/// same parse the engine loads. Every answer fails closed: a link or document
/// that cannot be evaluated is refused, and a scheme is blocked.
extension ExternalWebLink {
    // MARK: - Actions - Answer

    /// Whether another application, a drop, a peek, a popup or a menu item may
    /// hand Crest this URL as a web link: HTTP or HTTPS with a host.
    static func accepts(_ url: URL) -> Bool {
        let question = ExternalWebLink(scheme: url.scheme.nonEmpty, host: url.host(percentEncoded: false).nonEmpty)
        return (try? CrestCore.answer(question))?.accepted ?? false
    }
}
