import AppKit
import SwiftUI

/// The recent tabs while a Most Recent Tab shortcut is held: it begins on the
/// shortcut's key, follows the keys and the release of its modifiers, shows
/// the panel over the window once the hold lasts, and switches or cancels as
/// the person ends it. It also keeps each window's small pictures of the tabs
/// it leaves.
@MainActor
final class BrowserMacRecentTabSwitcher {
    // MARK: - Types

    /// A hold in progress.
    private struct Hold {
        let model: RecentTabSwitcherModel
        let window: NSWindow
        let chrome: BrowserChromeState
        let actions: BrowserCommandActions
        var isPresented = false
        var tasks: [Task<Void, Never>] = []
    }

    // MARK: - Static Variables

    /// How long the modifier is held before the panel shows.
    private static let showDelay: Duration = .milliseconds(100)
    /// How often the open panel reads the window's list again.
    private static let refreshInterval: Duration = .milliseconds(250)

    // MARK: - Variables

    private weak var shell: BrowserMacShell?
    private var hold: Hold?
    private var snapshots: [UUID: BrowserRecentTabSnapshots] = [:]
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []

    /// Whether the panel is up.
    var isShowingPanel: Bool { hold?.isPresented == true }

    // MARK: - Actions - Monitoring

    /// Watches modifier releases and clicks, and what takes Crest out of use.
    func start(in shell: BrowserMacShell) {
        guard monitors.isEmpty else { return }
        self.shell = shell
        monitors = [
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.modifiersChanged(ShortcutModifiers(event.modifierFlags))
                return event
            } as Any,
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
                [weak self] event in
                self?.mouseDown(event) == true ? nil : event
            } as Any,
        ]
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) {
                [weak self] note in
                let window = (note.object as AnyObject?).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    guard let self, window == self.hold.map({ ObjectIdentifier($0.window) }) else { return }
                    self.end(.cancel)
                }
            },
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.end(.cancel) }
            },
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.followKeyWindow() }
            },
            center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) {
                [weak self] note in
                let window = (note.object as AnyObject?).map(ObjectIdentifier.init)
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if window == self.hold.map({ ObjectIdentifier($0.window) }) { self.end(.cancel) }
                    self.forgetClosedWindows()
                }
            },
        ]
        followKeyWindow()
        followPreference()
    }

    /// Lets go of every picture once the preference goes off.
    private func followPreference() {
        withObservationTracking {
            _ = BrowserAppPreferenceStore.shared.showsRecentTabs
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !BrowserAppPreferenceStore.shared.showsRecentTabs {
                    for pictures in snapshots.values { pictures.removeAll() }
                }
                followPreference()
            }
        }
    }

    // MARK: - Actions - Holding

    /// Begins a hold for `direction`'s command, and answers whether it did.
    /// Nothing begins while the preference is off, in a window without a
    /// list, or when the shortcut has no modifier to hold; the command then
    /// jumps at once.
    func begin(direction: RecentTabSwitchDirection) -> Bool {
        guard hold == nil, BrowserAppPreferenceStore.shared.showsRecentTabs, let shell, let windows = shell.windows,
            let context = windows.activeContext, let actions = windows.activeActions,
            let window = NSApp.keyWindow, let shortcuts = shell.application?.shortcuts
        else { return false }
        let forward = shortcuts.shortcut(for: .mostRecentTab)
        let backward = shortcuts.shortcut(for: .mostRecentTabBackward)
        let isForward = direction == .forward
        guard let binding = isForward ? forward : backward else { return false }
        let other = isForward ? backward : forward
        let items = context.browser.recentTabItems()
        guard !items.isEmpty,
            let session = RecentTabSwitcherSession(
                direction: direction, binding: binding, otherBinding: other, items: items,
                rightToLeft: window.contentView?.userInterfaceLayoutDirection == .rightToLeft)
        else { return false }
        let model = RecentTabSwitcherModel(
            session: session, browser: context.browser, snapshots: snapshots(for: context))
        model.commit = { [weak self] index in self?.commit(index: index) }
        model.announce = { [weak self] text in self?.announce(text) }
        hold = Hold(model: model, window: window, chrome: context.chrome, actions: actions)
        hold?.tasks = [
            Task { [weak self] in
                try? await Task.sleep(for: Self.showDelay)
                guard !Task.isCancelled else { return }
                self?.showDelayElapsed()
            },
            Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.refreshInterval)
                    guard !Task.isCancelled else { return }
                    self?.refresh()
                }
            },
        ]
        return true
    }

    /// Takes a key down while a hold is on, and answers whether the switcher
    /// took it from the page.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let hold else { return false }
        guard let shortcut = BrowserShortcut(event: event) else { return hold.model.session.isShowing }
        let response = hold.model.session.keyDown(shortcut)
        if let outcome = response.outcome {
            end(outcome)
        } else {
            presentIfDue()
        }
        return response.isConsumed
    }

    // MARK: - Actions - Events

    private func modifiersChanged(_ modifiers: ShortcutModifiers) {
        guard let hold, let outcome = hold.model.session.modifiersChanged(to: modifiers) else { return }
        end(outcome)
    }

    private func showDelayElapsed() {
        guard let hold else { return }
        let modifiers = ShortcutModifiers(NSEvent.modifierFlags)
        if let outcome = hold.model.session.showDelayElapsed(modifiers: modifiers) {
            end(outcome)
        } else {
            presentIfDue()
        }
    }

    /// Clicks outside the open panel close it and go no further.
    private func mouseDown(_ event: NSEvent) -> Bool {
        guard let hold else { return false }
        if hold.isPresented, event.window === hold.window, let content = hold.window.contentView {
            var point = content.convert(event.locationInWindow, from: nil)
            if !content.isFlipped { point.y = content.bounds.height - point.y }
            if hold.model.panelFrame.contains(point) { return false }
        }
        let consumed = hold.isPresented
        end(.cancel)
        return consumed
    }

    private func commit(index: Int) {
        guard let hold, hold.model.session.items.indices.contains(index) else { return }
        hold.model.session.highlight(index: index)
        end(hold.model.session.finish())
    }

    /// Reads the window's list again, so a closed tab leaves the panel.
    private func refresh() {
        guard let hold else { return }
        if let outcome = hold.model.session.refresh(items: hold.model.browser.recentTabItems()) {
            end(outcome)
        }
    }

    // MARK: - Actions - Ending

    private func end(_ outcome: RecentTabSwitcherSession.Outcome) {
        guard let ended = hold else { return }
        hold = nil
        for task in ended.tasks { task.cancel() }
        if ended.isPresented { ended.chrome.recentTabs = nil }
        guard case .commit(let item) = outcome else { return }
        ended.actions.selectRecentTab(item)
    }

    // MARK: - Actions - Panel

    private func presentIfDue() {
        guard var current = hold, current.model.session.isShowing, !current.isPresented else { return }
        if let item = current.model.session.items.first {
            current.model.snapshots.capture(item.tabIDs, refreshing: true)
        }
        current.isPresented = true
        hold = current
        current.chrome.recentTabs = current.model
        announce(current.model.spokenTitle(at: current.model.session.highlightedIndex))
    }

    private func announce(_ text: String) {
        guard let hold, hold.isPresented, !text.isEmpty else { return }
        NSAccessibility.post(
            element: hold.window, notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
    }

    // MARK: - Actions - Snapshots

    /// Starts keeping pictures for the key window, once it is a browser window.
    private func followKeyWindow() {
        guard let context = shell?.windows?.activeContext else { return }
        _ = snapshots(for: context)
    }

    private func snapshots(for context: BrowserMacWindowContext) -> BrowserRecentTabSnapshots {
        if let existing = snapshots[context.windowID] { return existing }
        let access = shell?.application?.spaceAccess
        let created = BrowserRecentTabSnapshots(context: context) { access?.isLocked($0) ?? true }
        snapshots[context.windowID] = created
        created.followShownTabs()
        return created
    }

    private func forgetClosedWindows() {
        guard let windows = shell?.windows else { return }
        // The closing window is still listed during its notification.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            snapshots = snapshots.filter { id, _ in windows.window(for: id) != nil || windows.isPrivateWindow(id) }
        }
    }
}
