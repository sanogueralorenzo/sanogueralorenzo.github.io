import Foundation

extension PageFailure {
    /// The address that failed.
    var failingURL: URL? { url.flatMap(URL.init(string:)) }

    /// The site the failure names, as the failure page says it.
    var displayHost: String {
        failingURL?.host() ?? url ?? "this site"
    }
}
