import AppKit
import Observation

/// Small pictures of one window's recent tabs, kept in memory only and never
/// written anywhere. A tab is pictured once it has shown for a moment, while
/// its page still draws, and the panel pictures the tab it opens over; only
/// tabs on the window's recent list keep theirs. Nothing is pictured while the
/// preference is off or the Space is locked.
@MainActor
@Observable
final class BrowserRecentTabSnapshots {
    // MARK: - Static Variables

    /// The width each picture is taken at, in points.
    static let width: CGFloat = 320
    /// Pictures of one tab are never taken closer together than this, so
    /// going back and forth between tabs costs one picture each, not one per
    /// switch; the tab the panel opens over is pictured again as it opens.
    private static let minimumInterval: TimeInterval = 30
    /// How long a tab shows before it is pictured, so a switch never waits on
    /// a picture and a tab passed through on the way to another is skipped.
    private static let settleDelay: Duration = .milliseconds(1500)

    // MARK: - Variables

    private(set) var images: [UUID: NSImage] = [:]
    @ObservationIgnored private let context: BrowserMacWindowContext
    @ObservationIgnored private let isLocked: @MainActor (SpaceModel) -> Bool
    @ObservationIgnored private var lastCaptures: [UUID: Date] = [:]
    @ObservationIgnored private var isFollowing = false
    @ObservationIgnored private var settling: Task<Void, Never>?

    // MARK: - Initializers

    init(context: BrowserMacWindowContext, isLocked: @escaping @MainActor (SpaceModel) -> Bool) {
        self.context = context
        self.isLocked = isLocked
    }

    // MARK: - Actions - Following

    /// Pictures the tabs the window shows once they have shown for a moment,
    /// each time it shows others.
    func followShownTabs() {
        guard !isFollowing else { return }
        isFollowing = true
        settle()
        track()
    }

    private func track() {
        withObservationTracking {
            _ = context.browser.shownCards.map(\.id)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.settle()
                self?.track()
            }
        }
    }

    /// Pictures what the window shows after `settleDelay`, unless it shows
    /// something else by then.
    private func settle() {
        settling?.cancel()
        settling = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, let self else { return }
            capture(context.browser.shownCards.map(\.id))
        }
    }

    // MARK: - Actions - Capturing

    /// Pictures `tabIDs` of the Space the window shows, when they are resident,
    /// skipping a tab pictured moments ago unless `refreshing`.
    func capture(_ tabIDs: [UUID], refreshing: Bool = false) {
        guard BrowserAppPreferenceStore.shared.showsRecentTabs, let space = context.browser.shownSpace, !isLocked(space)
        else {
            return
        }
        let now = Date()
        for tabID in tabIDs {
            if !refreshing, let last = lastCaptures[tabID], now.timeIntervalSince(last) < Self.minimumInterval {
                continue
            }
            let assignment = BrowserTabRuntimeAssignment(tabID: tabID, spaceID: space.id, profileID: space.profileID)
            guard let page = context.pages.residentPage(matching: assignment) else { continue }
            lastCaptures[tabID] = now
            page.captureViewport(width: Self.width) { [weak self] image in
                guard let self, let image else { return }
                images[tabID] = image
                prune()
            }
        }
    }

    // MARK: - Actions - Keeping

    /// Lets go of the pictures of tabs the window no longer lists.
    func prune() {
        let listed = Set(context.browser.recentTabItems().flatMap(\.tabIDs))
        guard images.keys.contains(where: { !listed.contains($0) }) else { return }
        images = images.filter { listed.contains($0.key) }
        lastCaptures = lastCaptures.filter { listed.contains($0.key) }
    }

    /// Lets go of every picture, as when the preference goes off.
    func removeAll() {
        images = [:]
        lastCaptures = [:]
    }
}
