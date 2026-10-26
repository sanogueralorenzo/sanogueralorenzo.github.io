import Foundation

struct BrowserGitHubPullRequest: Decodable, Identifiable, Equatable {
    let url: URL
    let title: String
    let repository: String
    let number: Int
    let author: String

    var id: URL { url }

    static func accepts(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" && url.host == "github.com"
            && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
    }

    /// Website content cannot turn an integration row into an arbitrary link.
    var isValid: Bool {
        Self.accepts(url)
            && url.query == nil && url.fragment == nil
            && url.path == "/\(repository)/pull/\(number)"
            && repository.split(separator: "/").count == 2
            && number > 0 && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && title.count <= 512 && author.count <= 128
    }
}
