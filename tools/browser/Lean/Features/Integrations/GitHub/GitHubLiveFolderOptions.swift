import Foundation

struct GitHubLiveFolderOptions: Codable, Equatable {
    static let `default` = GitHubLiveFolderOptions()
    var intervalMinutes = 30
    var authorMe = true
    var assignedMe = true
    var reviewRequested = false
    var includeDrafts = true
    var excludedRepositories: [String] = []
}

enum BrowserGitHubFailure: Error, Equatable {
    case notSignedIn, unavailable, noFilters, invalidResponse
}
