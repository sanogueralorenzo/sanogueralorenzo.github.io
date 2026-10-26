import CoreGraphics
import Observation

/// What the recent tabs panel draws and how the pointer reaches the session:
/// the held session, the pictures and the stores that name each tab.
@MainActor
@Observable
final class RecentTabSwitcherModel {
    // MARK: - Variables

    var session: RecentTabSwitcherSession {
        didSet {
            guard session.isShowing, oldValue.highlightedIndex != session.highlightedIndex else { return }
            announce(spokenTitle(at: session.highlightedIndex))
        }
    }
    let browser: BrowserStore
    let snapshots: BrowserRecentTabSnapshots
    /// Commits the item at an index, as a click does.
    @ObservationIgnored var commit: @MainActor (Int) -> Void = { _ in }
    /// Tells VoiceOver which item the highlight reached.
    @ObservationIgnored var announce: @MainActor (String) -> Void = { _ in }

    /// Where each card sits in the panel's own coordinates, top left origin.
    @ObservationIgnored var cardFrames: [Int: CGRect] = [:]
    /// Where the panel sits in the window's content, top left origin, which
    /// tells a click on it from a click elsewhere in the window.
    @ObservationIgnored var panelFrame: CGRect = .null
    /// Where the pointer was when the panel first saw it. The panel follows
    /// the pointer only once it moves from there, so a pointer resting where
    /// the panel appears leaves the keyboard's highlight alone.
    @ObservationIgnored private var restingPointer: CGPoint?
    @ObservationIgnored private var hasPointerMoved = false

    // MARK: - Initializers

    init(session: RecentTabSwitcherSession, browser: BrowserStore, snapshots: BrowserRecentTabSnapshots) {
        self.session = session
        self.browser = browser
        self.snapshots = snapshots
    }

    // MARK: - Actions - Pointer

    /// Highlights the card under `point`, in the panel's coordinates, once the
    /// pointer has moved since the panel appeared.
    func pointerMoved(to point: CGPoint) {
        guard let resting = restingPointer else {
            restingPointer = point
            return
        }
        if !hasPointerMoved { hasPointerMoved = hypot(point.x - resting.x, point.y - resting.y) > 1 }
        guard hasPointerMoved, let index = cardFrames.first(where: { $0.value.contains(point) })?.key else { return }
        session.highlight(index: index)
    }

    // MARK: - Actions - Reading

    /// The tabs of `item` as the window's Space holds them, in display order.
    func tabs(of item: RecentTabItem) -> [TabStateModel] {
        guard let space = browser.shownSpace else { return [] }
        return item.tabIDs.compactMap { space.tabs.model($0) }
    }

    /// What VoiceOver says for the item at `index`.
    func spokenTitle(at index: Int) -> String {
        guard session.items.indices.contains(index) else { return "" }
        let title = tabs(of: session.items[index]).map(\.shownTitle).joined(separator: ", ")
        return String(localized: "\(title), \(index + 1) of \(session.items.count)")
    }
}
