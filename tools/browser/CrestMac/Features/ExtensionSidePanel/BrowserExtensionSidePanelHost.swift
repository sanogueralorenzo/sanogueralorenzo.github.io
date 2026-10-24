import AppKit
import Observation

/// One window's extension side panels.
///
/// A panel is a trailing column in the page row — the `.panel` slot the shared
/// split layout already reserves — and never a tab. It carries no session
/// membership, is not persisted and is not synced, so closing the window or
/// quitting leaves nothing behind. The engine owns each panel document; this
/// object owns only which one the window shows and how wide it is.
///
/// A panel belongs to the tab it was opened for, as Chromium's does. The window
/// shows the focused tab's own panel. Without one, the panel it was showing
/// stays only when its extension shows that same panel for the new tab too;
/// otherwise the card closes, and the panel waits with its own tab until that
/// tab has focus again.
@Observable
@MainActor
final class BrowserExtensionSidePanelHost {
    // MARK: - Types

    struct Panel: Identifiable {
        /// The owning extension's identifier.
        let id: String
        /// The page of the tab the panel was opened for, which keeps its
        /// document.
        let pageID: UUID
        let title: String
        let icon: NSImage?
        /// The engine's panel view. Mounted as-is; the host never reparents it.
        let view: NSView
        /// Tears the panel document down. Called only for a user dismissal —
        /// an engine-initiated one has already released it.
        let close: () -> Void
        /// Whether the panel also belongs beside the page that names another
        /// tab: its extension shows this one panel for both tabs. A panel the
        /// extension gave its own tab never does.
        let follows: (UUID) -> Bool
    }

    // MARK: - Variables

    /// The panel the window shows beside its focused tab.
    private(set) var panel: Panel?
    private(set) var width = BrowserSplitPanelLayoutMetrics.defaultWidth
    /// Each tab's own panel, by its page, whether or not the window shows it.
    @ObservationIgnored private var panels: [UUID: Panel] = [:]
    /// The page of the tab the window focuses, or nil while it shows no page.
    @ObservationIgnored private var focusedPageID: UUID?
    /// The panel that was showing when the window moved to a tab showing no
    /// page, which the next page's tab may still show.
    @ObservationIgnored private var carried: Panel?

    // MARK: - Actions - Panels

    /// The panel the tab showing `pageID` shows: the window's while that tab
    /// has focus, and otherwise the tab's own.
    func panel(on pageID: UUID) -> Panel? {
        pageID == focusedPageID ? panel : panels[pageID]
    }

    /// Keeps `panel` as its tab's own, in place of any other the tab had, and
    /// shows it while that tab has focus. The engine keeps one panel document
    /// per tab and has already released the other.
    func present(_ panel: Panel) {
        panels[panel.pageID] = panel
        guard panel.pageID == focusedPageID else { return }
        self.panel = panel
        carried = nil
    }

    /// The user closed the panel the window shows.
    func close() {
        guard let panel else { return }
        close(panel)
    }

    /// Closes the panel the tab showing `pageID` shows.
    func close(on pageID: UUID) {
        guard let panel = panel(on: pageID) else { return }
        close(panel)
    }

    /// The panel document or its extension host went away. The engine has
    /// already released the document, so this only drops the card.
    func dismiss(_ extensionID: String, from pageID: UUID) {
        forget { $0.pageID == pageID && $0.id == extensionID }
    }

    /// The page's panel document went away with the page, or gave way to
    /// another.
    func release(_ pageID: UUID) {
        forget { $0.pageID == pageID }
    }

    private func close(_ panel: Panel) {
        forget { $0.pageID == panel.pageID && $0.id == panel.id }
        panel.close()
    }

    private func forget(where matches: (Panel) -> Bool) {
        panels = panels.filter { !matches($0.value) }
        if let panel, matches(panel) { self.panel = nil }
        if let carried, matches(carried) { self.carried = nil }
    }

    // MARK: - Actions - Focus

    /// Follows the window to the tab showing `pageID`, or to a tab showing no
    /// page.
    func focus(on pageID: UUID?) {
        guard pageID != focusedPageID else { return }
        let previous = panel ?? carried
        focusedPageID = pageID
        guard let pageID else {
            carried = previous
            panel = nil
            return
        }
        carried = nil
        panel = panels[pageID] ?? previous.flatMap { $0.follows(pageID) ? $0 : nil }
    }

    // MARK: - Mutators

    func commitWidth(_ width: CGFloat) {
        self.width = BrowserSplitPanelLayoutMetrics.clampedWidth(width)
    }
}
