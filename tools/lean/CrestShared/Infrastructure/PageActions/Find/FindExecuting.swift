/// Page search options shared by native engine adapters. Every engine's find
/// wraps at the end of the page; Crest never asks for anything else.
struct BrowserFindConfiguration {
    var backwards = false
    var caseSensitive = false
}

/// Which match a search selected, out of how many the page holds.
struct BrowserFindMatches: Equatable, Sendable {
    /// The selected match, counted from 1.
    let active: Int
    let total: Int
}

/// What one search found. `matches` is nil when the engine cannot count them.
struct BrowserFindResult: Equatable, Sendable {
    let matchFound: Bool
    let matches: BrowserFindMatches?

    static let notFound = BrowserFindResult(matchFound: false, matches: nil)

    // MARK: - Initializers

    init(matchFound: Bool, matches: BrowserFindMatches? = nil) {
        self.matchFound = matchFound
        self.matches = matches
    }

    /// A result from an engine that counts: zero matches means nothing was
    /// found, and an ordinal outside the matches means none is selected.
    init(matchCount: Int, activeMatch: Int) {
        guard matchCount > 0 else {
            self.init(matchFound: false)
            return
        }
        self.init(
            matchFound: true,
            matches: (1...matchCount).contains(activeMatch)
                ? BrowserFindMatches(active: activeMatch, total: matchCount) : nil)
    }
}

@MainActor
protocol BrowserFindExecuting: AnyObject {
    func performFind(
        _ query: String,
        configuration: BrowserFindConfiguration,
        completion: @escaping @MainActor (BrowserFindResult) -> Void
    )
}
