import Foundation

/// What the shell and the engine adapter ask of a window by its identity in
/// the core, which runs the same store, page and window operations Crest's own
/// menus, Settings presentation and external-link handling run, so no adapter
/// edits the session, and the flush a quit waits for. Space selection stays
/// the window's own presentation state, changed the way the Space switcher
/// changes it.
extension BrowserMacApplication {
    // MARK: - Types

    /// The stores one window presents.
    private struct HostWindow {
        let browser: BrowserStore
        let pages: BrowserPagePool
        let chrome: BrowserChromeState
        let settings: BrowserSpaceSettingsPresentationState
        let windowState: BrowserWindowStateStore?
    }

    // MARK: - Variables

    /// The Spaces the engine's extensions may act in: every one this window
    /// family holds that is neither locked nor being deleted.
    var extensionSpaces: [BrowserSpaceIdentity] {
        browser.spaceModels.filter {
            !browser.deletingSpaceIDs.contains($0.id) && !spaceAccess.isLocked($0)
        }.map(\.identity)
    }

    // MARK: - Actions - Spaces

    /// Shows `spaceID` in the window `window`.
    func selectSpace(_ spaceID: UUID, in window: UUID) {
        hostWindow(window)?.browser.selectSpace(spaceID)
    }

    // MARK: - Actions - Tabs

    /// Shows `space` in `window` and opens `url` there as its selected tab.
    @discardableResult
    func openTab(_ url: URL, in space: BrowserSpaceRuntimeAssignment, window: UUID) -> Bool {
        guard let host = hostWindow(window), let target = host.browser.spaceModel(matching: space),
            !spaceAccess.isLocked(target)
        else { return false }
        host.browser.selectSpace(target.id)
        guard host.browser.openNewTab(url: url, matching: space) != nil else { return false }
        host.pages.select()
        return true
    }

    /// Opens a link another app sent in `space`, in `window`.
    @discardableResult
    func openExternalLink(_ url: URL, in space: BrowserSpaceRuntimeAssignment, window: UUID) -> Bool {
        guard let host = hostWindow(window), host.browser.openNewTab(url: url, matching: space) != nil
        else { return false }
        host.pages.select()
        host.pages.load(url)
        host.chrome.dismissCommandPalette()
        return true
    }

    func openSettings(in window: UUID) {
        guard let host = hostWindow(window) else { return }
        host.browser.openSettings()
        host.pages.select()
    }

    /// Opens Settings on the Extensions pane for `space`.
    func openExtensionSettings(for space: BrowserSpaceRuntimeAssignment, in window: UUID) {
        guard let host = hostWindow(window) else { return }
        host.settings.present(.extensions, assignment: space)
        host.browser.openSettings()
        host.pages.select()
    }

    func openGettingStarted(in window: UUID) {
        guard let host = hostWindow(window) else { return }
        host.browser.openGettingStarted()
        host.pages.select()
    }

    // MARK: - Actions - Lifecycle

    /// Returns once every edit the app accepted is on disk and staged for
    /// sync and every window's resident page state is written, or once a few
    /// seconds have passed. Quitting waits for it.
    func flushPendingPersistenceBeforeQuit() async {
        // Private and temporary windows keep nothing, and every other window
        // shares the persistent session, so one flush covers the edits of all.
        let pools = [pages] + windowCoordinator.openWindowPages
        // Reading each resident page's session state has to happen while the
        // pages are still resident.
        for pool in pools { pool.archiveResidentTabStates() }
        await BrowserPersistenceFlush().run { [browser] in
            await browser.flushPendingSyncPersistenceUntilSettled()
            for pool in pools { await pool.flushPendingTabStateWrites() }
        }
    }

    // MARK: - Mutators

    private func hostWindow(_ id: UUID) -> HostWindow? {
        if id == privatePages.windowID {
            return HostWindow(
                browser: privateBrowser, pages: privatePages, chrome: privateChrome,
                settings: spaceSettingsPresentation, windowState: nil)
        }
        guard let model = windowCoordinator.existingModel(for: id) else { return nil }
        return HostWindow(
            browser: model.browser, pages: model.pages, chrome: model.chrome,
            settings: model.spaceSettingsPresentation, windowState: model.windowState)
    }
}
