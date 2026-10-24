import SwiftUI

extension MobileBrowserRootModel {
    var commandController: MobileBrowserCommandController {
        MobileBrowserCommandController(browser: browser, pages: pages, spaceAccess: spaceAccess)
    }

    func commandContext(
        transientBrowsing: BrowserTransientBrowsingCoordinator,
        layoutDirection: LayoutDirection,
        usesPageToolbars: Bool,
        togglePrivateBrowsing: @escaping () -> Void,
        openNewTab: @escaping () -> Void,
        openLocation: @escaping () -> Void,
        prepareForSelectionSynchronization: @escaping () -> Void,
        toggleSidebar: @escaping () -> Void,
        presentHistory: @escaping () -> Void,
        presentArchive: @escaping () -> Void,
        presentDownloads: @escaping () -> Void
    ) -> MobileBrowserCommandContext {
        let controller = commandController
        let pageActions = selectedPageActions
        let contentBlockingAction = pageActions.map {
            MobileContentBlockingAction(browser: browser, pages: $0)
        }
        return MobileBrowserCommandContext(
            isPrivateBrowsing: browser.isPrivateBrowsing,
            canGoBack: pageActions?.canGoBack == true,
            canGoForward: pageActions?.canGoForward == true,
            hasSelectedTab: browser.shownTab != nil,
            hasActivePage: pageActions?.isAvailable == true,
            isLoading: pageActions?.activePage?.live.isLoading == true,
            canDismissSelectedTab: controller.canDismissSelectedTab
                && transientBrowsing.peekRequest == nil
                && transientBrowsing.quickWindowRequest == nil,
            canArchiveSelectedTab: controller.canArchiveSelectedTab
                && transientBrowsing.peekRequest == nil
                && transientBrowsing.quickWindowRequest == nil,
            canDuplicateSelectedTab: controller.canDuplicateSelectedTab,
            canReopenClosedTab: controller.canReopenClosedTab,
            tabCount: controller.tabCount,
            spaceCount: browser.spaceModels.count,
            numberedSelections: browser.core.numberedSelections(windowID: browser.windowID),
            isSelectedTabInSplit: controller.isSelectedTabInSplit,
            canSplitWithNextTab: controller.canSplitWithNextTab,
            layoutDirection: layoutDirection,
            isOffered: { [state = browser.core.state] in $0.isOffered(in: state) },
            readerModeActionTitle: pageActions?.readerModeActionTitle ?? "Show Reader",
            canToggleReaderMode: pageActions?.readerModeState.canToggle == true,
            canToggleTranslationToolbar: usesPageToolbars && pageActions?.isAvailable == true
                && pageActions?.readerModeState.isActive != true,
            isTranslationToolbarVisible: pageActions?.activePage?.translation.showsToolbar == true,
            contentBlockingActionTitle: ContentBlockingPolicy.switchTitle(
                for: browser.shownSpace?.settings.browsingPreferences.contentBlocking),
            openNewTab: openNewTab,
            togglePrivateBrowsing: togglePrivateBrowsing,
            openLocation: openLocation,
            goBack: { pageActions?.goBack() },
            goForward: { pageActions?.goForward() },
            reloadOrStop: { pageActions?.reloadOrStop() },
            stopLoading: { pageActions?.stopLoading() },
            reloadFromOrigin: { pageActions?.reloadFromOrigin() },
            toggleSelectedTabPinned: {
                _ = self.toggleSelectedTabPinnedFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            duplicateSelectedTab: {
                _ = self.duplicateSelectedTabFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            reopenClosedTab: {
                _ = self.reopenClosedTabFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            cleanupCurrentTabs: {
                self.cleanupCurrentTabsFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            dismissSelectedTab: {
                _ = self.dismissSelectedTabFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            archiveSelectedTab: {
                _ = self.archiveSelectedTabFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            selectPreviousTab: {
                _ = self.selectPreviousTabFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            selectNextTab: {
                _ = self.selectNextTabFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            selectMostRecentTab: {
                _ = self.selectMostRecentTabFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            selectTab: { tabID in
                _ = self.selectTabFromCommand(
                    tabID,
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            splitWithNextTab: {
                _ = self.splitWithNextTabFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            focusNextSplitCard: {
                _ = self.focusAdjacentSplitCardFromCommand(
                    offset: 1,
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            focusPreviousSplitCard: {
                _ = self.focusAdjacentSplitCardFromCommand(
                    offset: -1,
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            removeTabFromSplit: {
                _ = self.removeSelectedTabFromSplitFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            separateSplitTabs: {
                _ = self.separateSplitTabsFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            canMoveFocusedSplitCard: { offset in
                self.commandController.canMoveFocusedSplitCard(offset: offset)
            },
            moveFocusedSplitCard: { offset in
                _ = self.moveFocusedSplitCardFromCommand(offset: offset)
            },
            selectPreviousSpace: {
                _ = self.selectPreviousSpaceFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            selectNextSpace: {
                _ = self.selectNextSpaceFromCommand(
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            selectSpace: { spaceID in
                _ = self.selectSpaceFromCommand(
                    spaceID,
                    beforeSynchronization: prepareForSelectionSynchronization
                )
            },
            reopenArchivedTab: { tabID in
                self.browser.restoreArchivedTab(tabID)
            },
            toggleReaderMode: { pageActions?.toggleReaderMode() },
            setTranslationToolbarVisible: { visible in
                guard usesPageToolbars, pageActions?.readerModeState.isActive != true else { return }
                pageActions?.activePage?.translation.setToolbarVisible(visible)
            },
            toggleContentBlocking: {
                guard let contentBlockingAction else { return }
                _ = await contentBlockingAction.perform()
            },
            presentFind: { pageActions?.presentFind() },
            zoomIn: { pageActions?.zoomIn() },
            zoomOut: { pageActions?.zoomOut() },
            resetZoom: { pageActions?.resetZoom() },
            copyPageLink: { _ = pageActions?.copyPageLink() },
            copyPageLinkAsMarkdown: {
                _ = pageActions?.copyPageLinkAsMarkdown()
            },
            printPage: { pageActions?.printPage() },
            toggleSidebar: toggleSidebar,
            presentHistory: presentHistory,
            presentArchive: presentArchive,
            presentDownloads: presentDownloads
        )
    }

    @discardableResult
    func toggleSelectedTabPinnedFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.toggleSelectedTabPinned() != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    @discardableResult
    func duplicateSelectedTabFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.duplicateSelectedTab() != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    @discardableResult
    func reopenClosedTabFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.reopenClosedTab() != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    func cleanupCurrentTabsFromCommand(
        beforeSynchronization: () -> Void = {}
    ) {
        commandController.cleanupCurrentTabs()
        beforeSynchronization()
        synchronizeAfterCommandSelection()
    }

    @discardableResult
    func dismissSelectedTabFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.dismissSelectedTab() != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    @discardableResult
    func archiveSelectedTabFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.archiveSelectedTab() != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    @discardableResult
    func selectPreviousTabFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.selectPreviousTab() != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    @discardableResult
    func selectNextTabFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.selectNextTab() != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    @discardableResult
    func selectMostRecentTabFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.selectMostRecentTab() != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    @discardableResult
    func selectTabFromCommand(
        _ tabID: UUID,
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.selectNumberedTab(tabID) != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    @discardableResult
    func selectPreviousSpaceFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.selectPreviousSpace() != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    @discardableResult
    func selectNextSpaceFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.selectNextSpace() != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    @discardableResult
    func selectSpaceFromCommand(
        _ spaceID: UUID,
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.selectNumberedSpace(spaceID) != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    /// Moves focus between the cards already on screen.
    ///
    /// Deliberately does not run `synchronizeAfterCommandSelection()`: focus
    /// inside a presented split changes which card chrome speaks for and nothing
    /// about what is presented, so re-entering the compact page presentation
    /// would animate a transition to the surface already showing.
    @discardableResult
    func focusAdjacentSplitCardFromCommand(
        offset: Int,
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.focusAdjacentSplitCard(offset: offset) != nil
        else { return false }
        beforeSynchronization()
        address = browser.shownTab?.url ?? ""
        return true
    }

    /// Reorders the cards already on screen.
    ///
    /// Like the focus step, and for the same reason, this deliberately skips
    /// `synchronizeAfterCommandSelection()`: the selection does not move, so
    /// re-entering the compact page presentation would animate a transition to
    /// the surface already showing. The address bar keeps speaking for the same
    /// card, so it is not rewritten either.
    @discardableResult
    func moveFocusedSplitCardFromCommand(offset: Int) -> Bool {
        commandController.moveFocusedSplitCard(offset: offset) != nil
    }

    @discardableResult
    func splitWithNextTabFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.splitWithNextTab() != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    @discardableResult
    func removeSelectedTabFromSplitFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.removeSelectedTabFromSplit() != nil else {
            return false
        }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    @discardableResult
    func separateSplitTabsFromCommand(
        beforeSynchronization: () -> Void = {}
    ) -> Bool {
        guard commandController.separateSplitTabs() != nil else { return false }
        beforeSynchronization()
        synchronizeAfterCommandSelection()
        return true
    }

    private func synchronizeAfterCommandSelection() {
        address = browser.shownTab?.url ?? ""
        if browser.shownTab == nil {
            navigation.showTabViewer()
        } else {
            navigation.selectTab()
        }
    }
}
