// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Query construction follows Zen's GithubLiveFolder.sys.mjs.
import Foundation

extension GitHubLiveFolderOptions {
    var hasFilters: Bool { authorMe || assignedMe || reviewRequested }

    /// GitHub's JSON dashboard supports OR; the older HTML dashboard needs
    /// one query per relationship, just as Zen's provider does.
    func queries(jsonAPI: Bool) -> [String] {
        var base = ["is:pr", "is:open", "archived:false", "sort:updated-desc"]
        if !includeDrafts { base.append("draft:false") }
        base += excludedRepositories.map { "-repo:" + $0 }
        var relationships: [String] = []
        if authorMe { relationships.append("author:@me") }
        if assignedMe { relationships.append("assignee:@me") }
        if reviewRequested { relationships.append("review-requested:@me") }
        guard !relationships.isEmpty else { return [] }
        if jsonAPI { return [(base + ["(" + relationships.joined(separator: " OR ") + ")"]).joined(separator: " ")] }
        return relationships.map { (base + [$0]).joined(separator: " ") }
    }

    func matchesFilters(_ other: GitHubLiveFolderOptions) -> Bool {
        authorMe == other.authorMe && assignedMe == other.assignedMe && reviewRequested == other.reviewRequested
            && includeDrafts == other.includeDrafts && excludedRepositories == other.excludedRepositories
    }
}
