import Foundation
import OSLog

/// Tells the core what one page's engine shows and what its navigations and
/// icon do. Every engine binding feeds it the engine's own callbacks, so a
/// page reports the same events whichever engine hosts it:
///
/// - A navigation that loads a new document starts, commits, then finishes
///   with the title it settled on, or fails.
/// - A move within the document, such as `history.pushState` or a fragment,
///   starts and commits when the address changes, and finishes once the
///   page's title settles (see `titleSettleInterval`). A move while a new
///   document is still loading belongs to that load, which finishes it.
/// - An icon is reported when the engine finds one for the document, and
///   again when the page's theme changes the color behind it.
/// - What the page shows, its `PageSnapshot`, is reported at the end of any
///   main-queue turn in which the binding said it changed, and only when it
///   differs from the last one reported, so a burst of engine callbacks costs
///   the core one report. The snapshot carries the address a navigation that
///   has not committed is heading to, which this tracks.
/// - The page's back and forward history is read in the same turn and
///   reported only when it differs from the last one reported.
///
/// The core decides what each event records; this only decides when the
/// engine's callbacks amount to one.
@MainActor
final class EnginePageReporter {
    // MARK: - Static Variables

    /// How long a page's title must hold after a move within its document
    /// before the move finishes. Sites that route in script, such as video,
    /// mail and code hosts, change the address first and set the new page's
    /// title a moment later, sometimes through an interim one such as
    /// "Loading…". Finishing at once would record the previous page's title.
    static let titleSettleInterval: Duration = .milliseconds(500)

    /// The longest a move within the document waits for its title to settle,
    /// counted from the move, so a page whose title never stops changing, such
    /// as one counting unread mail, still records.
    static let titleSettleLimit: Duration = .seconds(2)

    /// The reporters whose page changed in this turn, reported together once
    /// it ends.
    private static var changedThisTurn: [EnginePageReporter] = []

    /// Times reading and reporting a page's history, for Instruments.
    private static let historySignposter = OSSignposter(subsystem: "com.pauldavis.crest", category: "PageHistory")

    // MARK: - Variables

    private let report: @MainActor (any EngineEvent, Data?) -> Void
    /// What the engine shows now, given the address a navigation that has not
    /// committed is heading to.
    private let snapshot: @MainActor (_ pendingURL: String?) -> PageSnapshot
    /// The engine's back and forward history now: its entries, oldest first,
    /// and the index of the one it shows, or nil while it has none to report.
    private let history: @MainActor () -> (entries: [PageHistoryEntry], current: Int)?
    private let pageID: UUID
    /// The last snapshot reported, which a new one must differ from.
    private var reported: PageSnapshot?
    /// The last history reported, which a new one must differ from.
    private var reportedHistory: PageHistoryReported?
    /// The page changed since its last report, which is due when the turn ends.
    private var isReportDue = false
    /// Where a navigation that has not committed is heading.
    private(set) var pendingURL: URL?
    /// The document's address as last reported.
    private var documentURL: URL?
    /// A navigation to a new document started and has not finished or failed.
    private var isLoadingDocument = false
    /// The move within the document waiting for its title, with the latest
    /// moment it may finish and the timer that finishes it.
    private var settling: (url: URL, deadline: ContinuousClock.Instant, timer: Task<Void, Never>)?
    /// The image the engine found for the document, and where.
    private var icon: (data: Data, url: URL)?
    /// The color the page's theme puts behind its icon.
    private var accent: TabIconAccent?

    // MARK: - Initializers

    /// A reporter for `pageID` that hands each event to `report`, with the
    /// image a `PageIconChanged` names, and reads what the engine shows from
    /// `snapshot`, which is given the pending address to carry, and its
    /// history from `history`.
    init(
        pageID: UUID, snapshot: @escaping @MainActor (_ pendingURL: String?) -> PageSnapshot,
        history: @escaping @MainActor () -> (entries: [PageHistoryEntry], current: Int)?,
        report: @escaping @MainActor (any EngineEvent, Data?) -> Void
    ) {
        self.pageID = pageID
        self.snapshot = snapshot
        self.history = history
        self.report = report
    }

    /// A reporter that reports through the engine hosting `page`.
    convenience init(
        page: CorePage, snapshot: @escaping @MainActor (_ pendingURL: String?) -> PageSnapshot,
        history: @escaping @MainActor () -> (entries: [PageHistoryEntry], current: Int)?
    ) {
        self.init(pageID: page.id, snapshot: snapshot, history: history) { [weak page] event, icon in
            page?.report(event, icon: icon)
        }
    }

    // MARK: - Actions - State

    /// What the page shows changed. The page reports once this turn ends,
    /// however often this is called before then.
    func stateChanged() {
        guard !isReportDue else { return }
        isReportDue = true
        Self.changedThisTurn.append(self)
        guard Self.changedThisTurn.count == 1 else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { Self.reportChangedPages() }
        }
    }

    private static func reportChangedPages() {
        let changed = changedThisTurn
        changedThisTurn = []
        for reporter in changed { reporter.reportState() }
    }

    private func reportState() {
        isReportDue = false
        let current = snapshot(pendingURL?.absoluteString)
        if current != reported {
            reported = current
            report(PageStateChanged(pageID: pageID, snapshot: current), nil)
        }
        reportHistory()
    }

    /// Reports the page's history at the end of this turn even when it
    /// matches the last one reported, for a core that asked for an entry the
    /// engine no longer keeps.
    func reportHistoryAgain() {
        reportedHistory = nil
        stateChanged()
    }

    private func reportHistory() {
        let interval = Self.historySignposter.beginInterval("Report Page History")
        defer { Self.historySignposter.endInterval("Report Page History", interval) }
        guard let (entries, current) = history() else { return }
        let event = PageHistoryReported(pageID: pageID, entries: entries, current: current)
        guard event != reportedHistory else { return }
        reportedHistory = event
        report(event, nil)
    }

    // MARK: - Actions - Navigation

    /// The page is heading to `url`: the app asked it to load the address, or
    /// the engine accepted a navigation of its document to it.
    func heading(to url: URL?) {
        guard let url else { return }
        pendingURL = url
        stateChanged()
    }

    /// A navigation to a new document began, toward `url` when the engine
    /// knows it yet.
    func started(_ url: URL?) {
        cancelSettling()
        isLoadingDocument = true
        if let url { pendingURL = url }
        stateChanged()
        report(NavigationStarted(pageID: pageID, url: url?.absoluteString ?? "", sameDocument: false), nil)
    }

    /// The server sent the navigation that has not committed on to `url`.
    func redirected(to url: URL) {
        pendingURL = url
        stateChanged()
    }

    /// The new document took effect at `url`, without the icon of the one it
    /// replaced.
    func committed(_ url: URL) {
        cancelSettling()
        documentURL = url
        pendingURL = nil
        icon = nil
        stateChanged()
        report(NavigationCommitted(pageID: pageID, url: url.absoluteString, sameDocument: false), nil)
    }

    /// The new document finished loading at `url`, titled `title`.
    func finished(_ url: URL, title: String?) {
        cancelSettling()
        isLoadingDocument = false
        documentURL = url
        pendingURL = nil
        stateChanged()
        report(NavigationFinished(pageID: pageID, url: url.absoluteString, title: title ?? ""), nil)
    }

    /// The navigation failed as `failure` describes, and its document records
    /// nothing.
    func failed(_ failure: PageFailure) {
        cancelSettling()
        isLoadingDocument = false
        pendingURL = nil
        stateChanged()
        report(NavigationFailed(pageID: pageID, failure: failure), nil)
    }

    /// The navigation stopped without failing, as one that became a download
    /// or was cancelled does, so no new document is loading.
    func interrupted() {
        isLoadingDocument = false
        pendingURL = nil
        stateChanged()
    }

    /// The engine's current history entry shows `url`, which ends a navigation
    /// heading there that commits nothing, as a move within the document does.
    func arrived(at url: URL?) {
        guard let url, url == pendingURL else { return }
        pendingURL = nil
        stateChanged()
    }

    /// The page's address changed without a new document: a move within the
    /// one it shows. It finishes once the title settles, unless a new
    /// document is loading, whose own finish covers it.
    func movedWithinDocument(to url: URL) {
        guard url != documentURL else { return }
        documentURL = url
        stateChanged()
        report(NavigationStarted(pageID: pageID, url: url.absoluteString, sameDocument: true), nil)
        report(NavigationCommitted(pageID: pageID, url: url.absoluteString, sameDocument: true), nil)
        guard !isLoadingDocument else { return }
        cancelSettling()
        let deadline = ContinuousClock.now + Self.titleSettleLimit
        settling = (url, deadline, settle(url, at: min(ContinuousClock.now + Self.titleSettleInterval, deadline)))
    }

    /// The page's title changed, which restarts the wait of a move within the
    /// document, never past its limit.
    func titleChanged() {
        stateChanged()
        guard let pending = settling else { return }
        pending.timer.cancel()
        settling = (
            pending.url, pending.deadline,
            settle(pending.url, at: min(ContinuousClock.now + Self.titleSettleInterval, pending.deadline))
        )
    }

    private func settle(_ url: URL, at instant: ContinuousClock.Instant) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            do { try await Task.sleep(until: instant, clock: .continuous) } catch { return }
            guard let self, self.settling?.url == url else { return }
            self.settling = nil
            self.report(
                NavigationFinished(pageID: self.pageID, url: url.absoluteString, title: self.snapshot(nil).title), nil)
        }
    }

    private func cancelSettling() {
        settling?.timer.cancel()
        settling = nil
    }

    // MARK: - Actions - Icon

    /// The engine found `data` as the icon of the document at `url`.
    func foundIcon(_ data: Data?, at url: URL?) {
        guard let data, !data.isEmpty, let url else { return }
        icon = (data, url)
        reportIcon()
    }

    /// The page's theme puts `accent` behind its icon.
    func themeChanged(_ accent: BrowserTabIconAccent?) {
        let accent = accent.map { TabIconAccent(red: $0.red, green: $0.green, blue: $0.blue) }
        guard accent != self.accent else { return }
        self.accent = accent
        reportIcon()
    }

    private func reportIcon() {
        guard let icon else { return }
        report(PageIconChanged(pageID: pageID, url: icon.url.absoluteString, accent: accent), icon.data)
    }
}
