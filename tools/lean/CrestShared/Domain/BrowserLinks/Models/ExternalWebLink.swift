import Foundation

/// Uses the URL facts Foundation reports, so eligibility matches the address WebKit loads.
struct ExternalWebLink: Sendable {
    let scheme: String?
    let host: String?

    var isAccepted: Bool {
        guard let host, !host.isEmpty, host.utf16.count <= 1_024,
            let scheme
        else { return false }
        return scheme.caseInsensitiveCompare("http") == .orderedSame
            || scheme.caseInsensitiveCompare("https") == .orderedSame
    }

    static func accepts(_ url: URL) -> Bool {
        ExternalWebLink(scheme: url.scheme.nonEmpty, host: url.host(percentEncoded: false).nonEmpty).isAccepted
    }
}
