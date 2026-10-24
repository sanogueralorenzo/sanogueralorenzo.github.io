import Foundation

// MARK: - Opening

extension BrowserStore {
    @discardableResult
    func openNewTab() -> UUID? {
        showStartPage(outsideSplits: false)
    }

    /// Presents the Start Page before the person chooses a restored tab.
    ///
    /// Launch presentation is intentionally runtime-only. The durable session
    /// keeps its restored selection, so merely opening and closing Crest does
    /// not turn the Start Page draft into the next "last active tab."
    @discardableResult
    func presentStartPageForLaunch() -> UUID? {
        showStartPage(outsideSplits: false)
    }

    /// Like launch presentation, entering an unloaded Space keeps the
    /// remembered tab intact and does not persist a replacement selection.
    @discardableResult
    func presentStartPageForSpaceEntry() -> UUID? {
        showStartPage(outsideSplits: true)
    }

    /// Shows a Start Page in the Space this window shows, which the core
    /// chooses or opens, and answers it.
    private func showStartPage(outsideSplits: Bool) -> UUID? {
        guard let space = shownSpace else { return nil }
        let opening = ShowStartPage(
            workspaceID: family.workspaceID, windowID: windowID, spaceID: space.id, tabID: UUID(),
            outsideSplits: outsideSplits)
        guard family.perform(opening, from: self) != nil else { return nil }
        return selectedTabID(in: space.id)
    }

    @discardableResult
    func openNewTab(url: URL) -> UUID? {
        guard let space = shownSpace else { return nil }
        return openSessionTab(.page(url), in: space.id, insertingAfter: selectedTabID(in: space.id))
    }

    @discardableResult
    func openNewTab(url: URL, in spaceID: UUID) -> UUID? {
        openNewTab(url: url, in: spaceID, selecting: true)
    }

    @discardableResult
    func openNewTab(
        url: URL,
        in spaceID: UUID,
        selecting: Bool
    ) -> UUID? {
        guard !isDeleting(spaceID), spaceModel(spaceID) != nil else { return nil }
        return openSessionTab(
            .page(url), in: spaceID, insertingAfter: selectedTabID(in: spaceID), shouldSelect: selecting)
    }

    @discardableResult
    func openNewTab(
        url: URL,
        matching assignment: BrowserSpaceRuntimeAssignment,
        selecting: Bool = true
    ) -> UUID? {
        guard spaceModel(matching: assignment) != nil else { return nil }
        return openNewTab(
            url: url,
            in: assignment.spaceID,
            selecting: selecting
        )
    }

    /// Opens `url` in a new tab of Space `spaceID` for a modified link,
    /// selected when `selecting`, and answers the tab with its Space.
    func openModifiedLink(_ url: URL, in spaceID: UUID, selecting: Bool) -> BrowserModifiedLinkRegistration? {
        guard let tabID = openNewTab(url: url, in: spaceID, selecting: selecting),
            let space = spaceModel(spaceID),
            let tab = space.tabs.model(tabID)
        else { return nil }
        return BrowserModifiedLinkRegistration(tab: tab, space: space)
    }

    /// Closes an open tab once its page agrees to go, which the core archives.
    /// A saved or pinned tab's page is put away by `BrowserDurableTabCloseAction`,
    /// which retires the page first, so this path leaves it alone.
    @discardableResult
    func closeTab(_ id: UUID, in spaceID: UUID) -> Bool {
        guard let space = spaceModel(spaceID), let tab = space.tabs.model(id), !tab.placement.isDurable
        else { return false }
        let assignment = BrowserTabRuntimeAssignment(tabID: id, spaceID: spaceID, profileID: space.profileID)
        // The core asks the tab's page whether it may go before it closes the tab.
        return performPageDismissal(of: [assignment]) { [weak self] in
            guard let self, self.spaceModel(spaceID) != nil else { return false }
            return self.closeSessionTab(id, in: spaceID)
        }
    }

    /// Opens an address another app handed Crest in the Space this window
    /// shows, as `openAddress` does.
    @discardableResult
    func openExternalURL(_ url: URL) -> Bool {
        guard ExternalWebLink.accepts(url), let space = shownSpace else { return false }
        return openAddress(url, in: space.id)
    }

    /// Opens `url` in a Space this window shows: the Start Page on show there
    /// takes it, or a new tab opens it, which the core decides.
    @discardableResult
    func openAddress(_ url: URL, in spaceID: UUID) -> Bool {
        let opening = OpenAddress(
            workspaceID: family.workspaceID, windowID: windowID, spaceID: spaceID, tabID: UUID(),
            address: url.absoluteString)
        return family.perform(opening, from: self) != nil
    }

}

// MARK: - Metadata

extension BrowserStore {
    /// The open tabs of `space`, which clearing puts away.
    private static func currentTabIDs(of space: SpaceModel) -> Set<UUID> {
        Set(space.tabs.models.filter { $0.placement == .current }.map(\.id))
    }

    @discardableResult
    func closeTab(_ id: UUID) -> Bool {
        guard let space = shownSpace, space.tabs.model(id)?.placement == .current else { return false }
        return closeTab(id, in: space.id)
    }

    func deleteTab(_ id: UUID, in spaceID: UUID) {
        guard let space = spaceModel(spaceID) else { return }
        _ = deleteTab(id, matching: BrowserSpaceRuntimeAssignment(space: space))
    }

    @discardableResult
    func closeTab(
        _ id: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard spaceModel(matching: assignment)?.tabs.model(id) != nil else { return false }
        return closeTab(id, in: assignment.spaceID)
    }

    @discardableResult
    func clearCurrentTabs(
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = spaceModel(matching: assignment) else { return false }
        let ids = Self.currentTabIDs(of: space)
        let tabs = ids.map { BrowserTabRuntimeAssignment(tabID: $0, spaceID: space.id, profileID: space.profileID) }
        return performPageDismissal(of: tabs) { [weak self] in
            guard let self, let current = self.spaceModel(matching: assignment), Self.currentTabIDs(of: current) == ids,
                self.clearSessionTabs(in: assignment.spaceID)
            else { return false }
            return true
        }
    }

    @discardableResult
    func deleteTab(
        _ id: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        let tab = BrowserTabRuntimeAssignment(tabID: id, spaceID: assignment.spaceID, profileID: assignment.profileID)
        return performPageDismissal(of: [tab]) { [weak self] in
            guard let self, self.deleteSessionTab(id, in: assignment.spaceID) else { return false }
            return true
        }
    }

    @discardableResult
    func setTabCustomTitle(
        _ title: String?,
        for id: UUID,
        in spaceID: UUID
    ) -> Bool {
        guard renameSessionTab(title, tabID: id, in: spaceID) else {
            return false
        }
        return true
    }

    @discardableResult
    func setTabCustomTitle(
        _ title: String?,
        for id: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard spaceModel(matching: assignment)?.tabs.model(id) != nil else { return false }
        return setTabCustomTitle(title, for: id, in: assignment.spaceID)
    }

    /// Gives the tab `emoji` as its icon, which the core refuses when its
    /// first character does not present as an emoji.
    func setTabEmojiIcon(_ emoji: String, for id: UUID, in spaceID: UUID) {
        _ = setSessionTabIcon(.emoji, emoji: emoji, tabID: id, in: spaceID)
    }

    @discardableResult
    func setTabEmojiIcon(
        _ emoji: String,
        for id: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard spaceModel(matching: assignment)?.tabs.model(id) != nil else { return false }
        return setSessionTabIcon(.emoji, emoji: emoji, tabID: id, in: assignment.spaceID)
    }

    func setTabFavicon(
        _ faviconData: Data,
        iconAccent: BrowserTabIconAccent?,
        for id: UUID,
        in spaceID: UUID
    ) {
        guard
            setSessionTabIcon(
                .pulled, faviconData: faviconData,
                iconAccent: iconAccent, tabID: id, in: spaceID)
        else { return }
    }

    @discardableResult
    func setTabFavicon(
        _ faviconData: Data,
        iconAccent: BrowserTabIconAccent?,
        for id: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard spaceModel(matching: assignment)?.tabs.model(id) != nil else { return false }
        return setSessionTabIcon(
            .pulled, faviconData: faviconData, iconAccent: iconAccent, tabID: id, in: assignment.spaceID)
    }

    func clearTabIcon(for id: UUID, in spaceID: UUID) {
        guard setSessionTabIcon(.automatic, tabID: id, in: spaceID) else { return }
    }

    @discardableResult
    func clearTabIcon(
        for id: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard spaceModel(matching: assignment)?.tabs.model(id) != nil else { return false }
        return setSessionTabIcon(.automatic, tabID: id, in: assignment.spaceID)
    }

    @discardableResult
    func replaceTabSavedLocationWithCurrent(
        _ id: UUID,
        in spaceID: UUID
    ) -> Bool {
        replaceSessionSavedAddress(tabID: id, in: spaceID)
    }

    @discardableResult
    func restoreTabSavedLocation(
        _ id: UUID,
        in spaceID: UUID
    ) -> URL? {
        guard returnSessionTabToSavedAddress(tabID: id, in: spaceID) else { return nil }
        return spaceModel(spaceID)?.tabs.model(id)?.address
    }

    /// Archives the tab this window shows, where the core allows it.
    @discardableResult
    func archiveSelectedTab() -> UUID? {
        guard allows(.archiveTab), let space = shownSpace, let tab = shownTab, closeTab(tab.id, in: space.id) else {
            return nil
        }
        return tab.id
    }

    /// Gives the selected tab `url` to load when it shows a native view or the
    /// Start Page, so a page can open for it. An existing web page stays at its
    /// accepted location until its engine reports the new navigation, which
    /// the core records.
    /// Gives the selected tab, while it shows a native view or the Start
    /// Page, the address `input` names by its Space's rules, so a page can
    /// open for it. False when it changed nothing: the tab shows a web page,
    /// the input was blank, or a rule refused it.
    @discardableResult
    func navigateSelectedTab(to input: String) -> Bool {
        guard let space = shownSpace, let tab = shownTab, !tab.surface.showsPage else { return false }
        return family.send(
            NavigateTab(
                workspaceID: family.workspaceID, spaceID: space.id, tabID: tab.id, input: input),
            from: self, failure: "Core navigation failed")
    }

}

// MARK: - Residency

extension BrowserStore {
    @discardableResult
    func setTabKeepsPageLoaded(
        _ keepsPageLoaded: Bool,
        for id: UUID,
        in spaceID: UUID
    ) -> Bool {
        guard
            setSessionTabResidency(
                keepsPageLoaded,
                tabID: id,
                in: spaceID
            )
        else { return false }
        return true
    }

    @discardableResult
    func setTabKeepsPageLoaded(
        _ keepsPageLoaded: Bool,
        for id: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard spaceModel(matching: assignment)?.tabs.model(id) != nil else { return false }
        return setTabKeepsPageLoaded(
            keepsPageLoaded,
            for: id,
            in: assignment.spaceID
        )
    }
}
