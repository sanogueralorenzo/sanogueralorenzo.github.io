import Foundation

extension BrowserPeekRequest: MobileBrowserTransientRequest {
    // MARK: - Variables

    var isQuickWindow: Bool { false }
    var accessibilityLabel: String { "Peek from \(sourceTitle)" }
    var accessibilityIdentifier: String { "mobile-peek-overlay" }
    var previewSystemImage: String { "eye" }

    var overlayVocabulary: BrowserTransientOverlayVocabulary {
        BrowserTransientOverlayVocabulary(
            closeAccessibilityLabel: "Close Peek",
            closeHelp: "Close Peek (Esc or ⌘W)",
            loadingTitle: "Opening Peek…",
            releasedTitle: "Peek Released",
            releasedDescription:
                "Crest released this temporary page to reduce memory use.",
            restoreTitle: "Reload Page"
        )
    }

    // MARK: - Actions - Presentation

    func motionState(in coordinator: BrowserTransientBrowsingCoordinator) -> BrowserPeekMotionState? {
        coordinator.motionState(for: self)
    }

    func isPresented(by coordinator: BrowserTransientBrowsingCoordinator) -> Bool {
        coordinator.isPresentingPeek(self)
    }

    func dismiss(from coordinator: BrowserTransientBrowsingCoordinator) {
        coordinator.dismissPeek(self)
    }

    func close(on overlay: MobileBrowserTransientOverlayModel) {
        overlay.coordinator.dismissPeek(self)
    }

    func selectLockedSpace(
        _ assignment: BrowserSpaceRuntimeAssignment,
        on overlay: MobileBrowserTransientOverlayModel
    ) {
        guard let candidate = overlay.browser.spaceModel(matching: assignment),
            !overlay.spaceAccess.isLocked(candidate),
            overlay.coordinator.dismissPeek(self)
        else { return }
        overlay.browser.selectSpace(assignment.spaceID)
    }

    // MARK: - Actions - Page

    func makePageLease(
        for overlay: MobileBrowserTransientOverlayModel,
        from pages: MobileBrowserPageStore,
        in space: SpaceModel
    ) -> MobileBrowserTransientPageLease? {
        pages.makePeekPageLease(
            request: self, in: space,
            onDownloadOnlyNavigation: { [weak coordinator = overlay.coordinator] in
                coordinator?.dismissPeek(self)
            })
    }

    func rememberKeeping(
        _ page: MobileBrowserPage,
        in destinationAssignment: BrowserSpaceRuntimeAssignment,
        preferences: BrowserTransientBrowsingPreferences
    ) {}

    func release(_ lease: MobileBrowserTransientPageLease, on overlay: MobileBrowserTransientOverlayModel) {
        lease.release()
    }

    func disappear(from overlay: MobileBrowserTransientOverlayModel) {
        if overlay.isCurrentRequest {
            overlay.pageLease?.setActive(false)
        } else {
            overlay.pageLease?.release()
        }
    }
}
