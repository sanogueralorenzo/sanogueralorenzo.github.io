// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Dashboard formats/selectors adapted from zen-browser/desktop's
// GithubLiveFolder.sys.mjs, commit 2ad194525da74d7f00609a424d93a3c7db430d21.
import Foundation

@MainActor
final class BrowserGitHubClient {

    private struct Dashboard: Decodable {
        struct Payload: Decodable {
            struct Content: Decodable {
                struct Item: Decodable {
                    struct Author: Decodable { let displayLogin: String }
                    let permalink: URL
                    let title: String
                    let repoNameWithOwner: String
                    let number: Int
                    let author: Author
                }
                let results: [Item]
            }
            let pullsDashboardSurfaceContentRoute: Content
        }
        let payload: Payload
    }

    private var isJSONAPI: Bool?

    func reset() { isJSONAPI = nil }

    func read(from session: BrowserGitHubSession, options: GitHubLiveFolderOptions = .default) async throws
        -> [BrowserGitHubPullRequest]
    {
        guard options.hasFilters else { throw BrowserGitHubFailure.noFilters }
        var collected: [BrowserGitHubPullRequest] = []
        var seen: Set<URL> = []
        if isJSONAPI == nil {
            let probe = try await session.fetchPullRequests()
            isJSONAPI = Self.decodeJSON(probe) != nil
        }
        for query in options.queries(jsonAPI: isJSONAPI == true) {
            let data = try await session.fetchPullRequests(query: query)
            if isJSONAPI == true, Self.decodeJSON(data) == nil {
                isJSONAPI = false
                throw BrowserGitHubFailure.invalidResponse
            }
            let items = try await Self.parse(data)
            guard items.allSatisfy(\.isValid) else { throw BrowserGitHubFailure.invalidResponse }
            for item in items where seen.insert(item.url).inserted && collected.count < 100 {
                collected.append(item)
            }
        }
        try await session.validate()
        try Task.checkCancellation()
        return collected
    }

    private nonisolated static func parse(_ data: Data) async throws -> [BrowserGitHubPullRequest] {
        guard data.count <= 5 * 1_024 * 1_024, let text = String(data: data, encoding: .utf8) else {
            throw BrowserGitHubFailure.invalidResponse
        }
        if let items = decodeJSON(data) { return items }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") else {
            throw BrowserGitHubFailure.invalidResponse
        }
        // Parse dashboard HTML as inert XML to avoid loading page resources.
        let document = try XMLDocument(xmlString: text, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever])
        for script in try document.nodes(forXPath: "//script[@type='application/json']") {
            if let body = script.stringValue?.data(using: .utf8), let items = decodeJSON(body) { return items }
        }
        let actor = try document.nodes(forXPath: "//meta[@name='octolytics-actor-login']/@content").first?.stringValue
        guard let actor, !actor.isEmpty else { throw BrowserGitHubFailure.notSignedIn }
        let rows = try document.nodes(forXPath: "//div[starts-with(@id, 'issue_')]")
        guard
            try !rows.isEmpty
                || !(try document.nodes(
                    forXPath:
                        "//*[contains(concat(' ', normalize-space(@class), ' '), ' blankslate ') or @data-testid='issue-list-empty-state']"
                )).isEmpty
        else { throw BrowserGitHubFailure.invalidResponse }
        return try rows.map { row in
            guard let title = try row.nodes(forXPath: ".//a[starts-with(@id, 'issue_')]").first as? XMLElement,
                let href = title.attribute(forName: "href")?.stringValue,
                let url = URL(string: href, relativeTo: URL(string: "https://github.com"))?.absoluteURL
            else { throw BrowserGitHubFailure.invalidResponse }
            let parts = url.path.split(separator: "/")
            guard parts.count == 4, let number = Int(parts[3]) else { throw BrowserGitHubFailure.invalidResponse }
            let author =
                try row.nodes(forXPath: ".//*[contains(concat(' ', normalize-space(@class), ' '), ' opened-by ')]//a")
                .first?.stringValue ?? ""
            return BrowserGitHubPullRequest(
                url: url, title: (title.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                repository: parts.prefix(2).joined(separator: "/"), number: number,
                author: author.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private nonisolated static func decodeJSON(_ data: Data) -> [BrowserGitHubPullRequest]? {
        guard let dashboard = try? JSONDecoder().decode(Dashboard.self, from: data) else { return nil }
        return dashboard.payload.pullsDashboardSurfaceContentRoute.results.map {
            BrowserGitHubPullRequest(
                url: $0.permalink, title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines),
                repository: $0.repoNameWithOwner, number: $0.number, author: $0.author.displayLogin)
        }
    }
}
