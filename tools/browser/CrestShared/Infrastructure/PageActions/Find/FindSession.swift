import Observation

@Observable
@MainActor
final class BrowserFindSession {
    private(set) var isPresented: Bool {
        get { observed(\.isPresentedStorage, as: \.isPresented) }
        set { publish(newValue, into: \.isPresentedStorage, as: \.isPresented) }
    }
    @ObservationIgnored private var isPresentedStorage = false
    private(set) var matchState = BrowserFindMatchState.idle
    /// Which match the last completed search selected, out of how many; nil
    /// when nothing was found or the engine cannot count.
    private(set) var matches: BrowserFindMatches?
    private(set) var query = ""

    /// Bumped every time the page is asked for find, presented or not.
    ///
    /// Asking for find is always a request for the query field, and the bar is
    /// often already on screen when it is asked for a second time — the reader
    /// searched, clicked into the page, and reached for the shortcut again.
    /// `isPresented` cannot carry that: it is already true, so nothing the bar
    /// observes changes and the field stays wherever focus went. This counter
    /// changes on every ask, which is what the bar takes focus from.
    private(set) var focusRequest = 0

    /// Whether the bar should take the query field when it appears. Finding
    /// again brings a closed bar back to show where the match went, without
    /// pulling the keys away from the page the reader is stepping through.
    private(set) var focusesQueryField = true

    /// The last query searched for, which finding again reuses after the bar
    /// has closed and cleared its own.
    @ObservationIgnored private var lastQuery = ""

    @ObservationIgnored private var generation = 0

    /// Whether there is a query to find again: the bar's own while it is open,
    /// or the last one searched for once it has closed.
    var canFindAgain: Bool {
        !queryToFindAgain.isEmpty
    }

    private var queryToFindAgain: String {
        isPresented ? query : lastQuery
    }

    func present(hasLoadedPage: Bool) {
        guard hasLoadedPage else { return }
        isPresented = true
        focusesQueryField = true
        focusRequest &+= 1
    }

    /// Moves to the next or previous match for the query there is to find
    /// again, bringing the bar back without its field's focus when it closed.
    func findAgain(
        _ direction: BrowserFindDirection,
        hasLoadedPage: Bool,
        using executor: any BrowserFindExecuting
    ) {
        let query = queryToFindAgain
        guard hasLoadedPage, !query.isEmpty else { return }
        if !isPresented {
            isPresented = true
            focusesQueryField = false
        }
        find(query, direction: direction, using: executor)
    }

    func dismiss(using executor: any BrowserFindExecuting) {
        generation &+= 1
        matchState = .idle
        matches = nil
        query = ""
        isPresented = false
        clear(using: executor)
    }

    func find(
        _ query: String,
        direction: BrowserFindDirection = .forward,
        using executor: any BrowserFindExecuting
    ) {
        generation &+= 1
        self.query = query
        if !query.isEmpty { lastQuery = query }
        let requestGeneration = generation
        guard !query.isEmpty else {
            matchState = .idle
            matches = nil
            clear(using: executor)
            return
        }

        matchState = .searching
        executor.performFind(
            query,
            configuration: Self.configuration(for: direction)
        ) { [weak self] result in
            guard let self, generation == requestGeneration else { return }
            matchState = result.matchFound ? .found : .notFound
            matches = result.matchFound ? result.matches : nil
        }
    }

    private func clear(using executor: any BrowserFindExecuting) {
        executor.performFind("", configuration: BrowserFindConfiguration()) { _ in }
    }

    private static func configuration(
        for direction: BrowserFindDirection
    ) -> BrowserFindConfiguration {
        var configuration = BrowserFindConfiguration()
        configuration.backwards = direction == .backward
        configuration.caseSensitive = false
        return configuration
    }
}

extension BrowserFindSession: BrowserStoreFirstObservable {}
