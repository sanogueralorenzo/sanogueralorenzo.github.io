import Foundation

/// What a find-in-page search has turned up so far.
struct BrowserFindMatchState: Hashable, Sendable {
    // MARK: - Static Variables

    /// No search has been asked for, so there is nothing to say.
    static let idle = BrowserFindMatchState(name: "idle", label: nil, symbol: nil)
    static let searching = BrowserFindMatchState(
        name: "searching", label: "Searching", symbol: nil, showsProgress: true)
    static let found = BrowserFindMatchState(
        name: "found", label: "Match found", symbol: "checkmark.circle.fill", readsAsSuccess: true)
    static let notFound = BrowserFindMatchState(
        name: "notFound", label: "No match", symbol: "exclamationmark.circle.fill", readsAsFailure: true)

    /// Every state.
    static let all: [BrowserFindMatchState] = [idle, searching, found, notFound]

    // MARK: - Variables

    let name: String

    /// The state in words, also its accessibility label where a symbol stands
    /// in for them.
    let label: LocalizedStringResource?

    /// The symbol that stands for the state where there is no room for words.
    let symbol: String?

    /// Whether a spinner stands for the state where there is no room for words.
    let showsProgress: Bool

    /// Whether the search plainly found something, which the state's symbol
    /// shows.
    let readsAsSuccess: Bool

    /// Whether the page has nothing to show, which both the state's words and
    /// its symbol show.
    let readsAsFailure: Bool

    // MARK: - Initializers

    private init(
        name: String, label: LocalizedStringResource?, symbol: String?, showsProgress: Bool = false,
        readsAsSuccess: Bool = false, readsAsFailure: Bool = false
    ) {
        self.name = name
        self.label = label
        self.symbol = symbol
        self.showsProgress = showsProgress
        self.readsAsSuccess = readsAsSuccess
        self.readsAsFailure = readsAsFailure
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserFindMatchState, rhs: BrowserFindMatchState) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
