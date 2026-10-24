import Foundation

extension BrowserQuickWindowRequest: MobileBrowserTransientRequest {
    // MARK: - Variables

    var isQuickWindow: Bool { true }
    var accessibilityLabel: String { "Quick Window" }
    var accessibilityIdentifier: String { "mobile-quick-window-overlay" }
    var previewSystemImage: String { "sparkle.magnifyingglass" }

    var overlayVocabulary: BrowserTransientOverlayVocabulary {
        BrowserTransientOverlayVocabulary(
            closeAccessibilityLabel: "Close Quick Window",
            closeHelp: "Close Quick Window (Esc or ⌘W)",
            loadingTitle: "Opening Quick Window…",
            releasedTitle: "Quick Window Released",
            releasedDescription:
                "Crest released this temporary page to reduce memory use.",
            restoreTitle: "Reload Page"
        )
    }

    // MARK: - Actions - Presentation

    func motionState(in coordinator: BrowserTransientBrowsingCoordinator) -> BrowserPeekMotionState? {
        nil
    }

    func isSelected(in browser: BrowserStore) -> Bool {
        true
    }

    func hasSource(in browser: BrowserStore) -> Bool {
        browser.spaceModel(matching: spaceAssignment) != nil
    }

    func isPresented(by coordinator: BrowserTransientBrowsingCoordinator) -> Bool {
        coordinator.isPresentingQuickWindow(self)
    }

    func dismiss(from coordinator: BrowserTransientBrowsingCoordinator) {
        coordinator.dismissQuickWindow(self)
    }

    func close(on overlay: MobileBrowserTransientOverlayModel) {
        overlay.archiveCurrentSnapshot()
        overlay.coordinator.dismissQuickWindow(self)
    }

    func selectLockedSpace(
        _ assignment: BrowserSpaceRuntimeAssignment,
        on overlay: MobileBrowserTransientOverlayModel
    ) {
        overlay.changeSpace(of: self, to: assignment)
    }

    // MARK: - Actions - Page

    func makePageLease(
        for overlay: MobileBrowserTransientOverlayModel,
        from pages: MobileBrowserPageStore,
        in space: SpaceModel
    ) -> MobileBrowserTransientPageLease? {
        pages.makeTransientPageLease(
            url: overlay.releasedPageSnapshot?.url ?? url,
            in: space,
            onUserActivity: overlay.recordUserActivity,
            onDownloadOnlyNavigation: { [weak overlay] in
                overlay?.dismissDownloadOnlyNavigation()
            }
        )
    }

    // Keeping a Quick Window's page in another Space remembers that Space for its site.
    func rememberKeeping(
        _ page: MobileBrowserPage,
        in destinationAssignment: BrowserSpaceRuntimeAssignment,
        preferences: BrowserTransientBrowsingPreferences
    ) {
        guard destinationAssignment != assignment, let pageURL = page.live.documentURL ?? initialURL else { return }
        preferences.rememberSpace(destinationAssignment.spaceID, for: pageURL)
    }

    /// A Quick Window keeps what it shows: the snapshot it archives on
    /// dismissal, and the core's memory of the page, both until the snapshot
    /// goes.
    func release(_ lease: MobileBrowserTransientPageLease, on overlay: MobileBrowserTransientOverlayModel) {
        overlay.unload(lease)
    }

    func disappear(from overlay: MobileBrowserTransientOverlayModel) {
        overlay.archiveCurrentSnapshot()
        overlay.pageLease?.release()
    }
}
