import Foundation

// MARK: - Organization

extension BrowserStore {
    /// Pins a tab of the Space this window shows, or returns a pinned one to
    /// the open tabs, as the core places each. False when the core refused it.
    @discardableResult
    func togglePin(_ id: UUID) -> Bool {
        guard let space = shownSpace else { return false }
        return family.send(TogglePin(workspaceID: family.workspaceID, spaceID: space.id, tabID: id), from: self)
    }

    func pinTab(_ id: UUID) {
        guard let tab = shownSpace?.tabs.model(id), tab.placement != .pinned else { return }
        togglePin(id)
    }

    func saveTab(_ id: UUID) {
        let folderID = shownSpace?.folders.models.first { $0.location == .saved }?.id
        guard let tab = shownSpace?.tabs.model(id), tab.placement != .saved || tab.folderID != folderID else { return }
        moveTab(id, to: .saved, folderID: folderID)
    }

    @discardableResult
    func moveTab(
        _ id: UUID,
        from sourceSpaceID: UUID? = nil,
        to placement: TabPlacement,
        folderID: UUID? = nil,
        before destinationTabID: UUID? = nil
    ) -> Bool {
        guard let actualSourceSpace = spaceModels.first(where: { $0.tabs.model(id) != nil }),
            !isDeleting(actualSourceSpace.id), !isDeleting(selectedSpaceID),
            sourceSpaceID == nil || sourceSpaceID == actualSourceSpace.id
        else {
            return false
        }
        let actualSourceSpaceID = actualSourceSpace.id

        let moved: Bool
        if actualSourceSpaceID == selectedSpaceID {
            // The core takes a tab out of its split for a section that keeps none.
            moved = moveSessionTab(
                id, in: actualSourceSpaceID, to: placement, folderID: folderID, before: destinationTabID)
        } else {
            moved = moveTabBetweenSpaces(
                id,
                from: actualSourceSpaceID,
                into: selectedSpaceID,
                to: placement,
                folderID: folderID,
                before: destinationTabID
            )
        }
        guard moved else { return false }
        if actualSourceSpaceID != selectedSpaceID {
            guard let destinationSpace = shownSpace else { return false }
            interactionObserver?.browserDidMoveTab(
                from: BrowserTabRuntimeAssignment(
                    tabID: id, spaceID: actualSourceSpace.id, profileID: actualSourceSpace.profileID),
                to: BrowserSpaceRuntimeAssignment(space: destinationSpace)
            )
        }
        return true
    }

    @discardableResult
    func moveTab(
        _ id: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment,
        to placement: TabPlacement,
        folderID: UUID? = nil,
        before destinationTabID: UUID? = nil
    ) -> Bool {
        guard let space = spaceModel(matching: assignment), selectedSpaceID == assignment.spaceID,
            space.tabs.model(id) != nil
        else { return false }
        return moveSessionTab(id, in: assignment.spaceID, to: placement, folderID: folderID, before: destinationTabID)
    }

    @discardableResult
    func moveTab(
        _ item: BrowserTabDragItem,
        to placement: TabPlacement,
        folderID: UUID? = nil,
        before destinationTabID: UUID? = nil
    ) -> Bool {
        guard let destination = shownSpace else { return false }
        return moveTab(
            item, to: placement, folderID: folderID, before: destinationTabID,
            matching: BrowserSpaceRuntimeAssignment(space: destination))
    }

    @discardableResult
    func moveTab(
        _ item: BrowserTabDragItem,
        to placement: TabPlacement,
        folderID: UUID? = nil,
        before destinationTabID: UUID? = nil,
        matching destinationAssignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        let sourceAssignment = item.spaceAssignment
        guard let source = spaceModel(matching: sourceAssignment), source.tabs.model(item.tabID) != nil,
            spaceModel(matching: destinationAssignment) != nil, selectedSpaceID == destinationAssignment.spaceID
        else { return false }

        let moved: Bool
        if sourceAssignment == destinationAssignment {
            moved = moveSessionTab(
                item.tabID, in: sourceAssignment.spaceID, to: placement, folderID: folderID, before: destinationTabID)
        } else {
            moved = moveTabBetweenSpaces(
                item.tabID,
                from: sourceAssignment.spaceID,
                into: destinationAssignment.spaceID,
                to: placement,
                folderID: folderID,
                before: destinationTabID
            )
        }
        guard moved else { return false }
        if sourceAssignment != destinationAssignment {
            interactionObserver?.browserDidMoveTab(from: item.runtimeAssignment, to: destinationAssignment)
        }
        return true
    }

    func canMoveTab(_ id: UUID, from sourceSpaceID: UUID, into destinationSpaceID: UUID) -> Bool {
        guard !isDeleting(sourceSpaceID), !isDeleting(destinationSpaceID), sourceSpaceID != destinationSpaceID,
            spaceModel(sourceSpaceID)?.tabs.contains(id) == true, spaceModel(destinationSpaceID) != nil
        else { return false }
        return family.canSend(
            MoveTabToSpace(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: sourceSpaceID,
                tabID: id, destinationSpaceID: destinationSpaceID, placement: nil, folderID: nil,
                beforeTabID: nil, follows: false),
            from: self)
    }

    func canMoveTab(
        _ id: UUID,
        matching sourceAssignment: BrowserSpaceRuntimeAssignment,
        into destinationAssignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let source = spaceModel(matching: sourceAssignment), source.tabs.model(id) != nil,
            spaceModel(matching: destinationAssignment) != nil
        else { return false }
        return canMoveTab(
            id,
            from: sourceAssignment.spaceID,
            into: destinationAssignment.spaceID
        )
    }

    @discardableResult
    func moveTab(
        _ id: UUID,
        from sourceSpaceID: UUID,
        into destinationSpaceID: UUID
    ) -> Bool {
        guard !isDeleting(sourceSpaceID), !isDeleting(destinationSpaceID),
            let sourceSpace = spaceModel(sourceSpaceID), sourceSpace.tabs.contains(id)
        else { return false }
        let source = BrowserTabRuntimeAssignment(tabID: id, spaceID: sourceSpaceID, profileID: sourceSpace.profileID)
        guard moveTabBetweenSpaces(id, from: sourceSpaceID, into: destinationSpaceID),
            let destinationSpace = spaceModel(destinationSpaceID)
        else { return false }
        interactionObserver?.browserDidMoveTab(from: source, to: BrowserSpaceRuntimeAssignment(space: destinationSpace))
        return true
    }

    /// A followed move explicitly opens one tab in its new profile. Ordinary
    /// Space entry must still leave remembered unloaded tabs alone.
    @discardableResult
    func consumeMovedTabActivation() -> Bool {
        guard let activation = pendingMovedTabActivation else { return false }
        pendingMovedTabActivation = nil
        return shownTabAssignment == activation
    }

    private func moveTabBetweenSpaces(
        _ id: UUID,
        from sourceSpaceID: UUID,
        into destinationSpaceID: UUID,
        to placement: TabPlacement? = nil,
        folderID: UUID? = nil,
        before destinationTabID: UUID? = nil
    ) -> Bool {
        guard spaceModel(sourceSpaceID) != nil, let destination = spaceModel(destinationSpaceID) else { return false }
        let follows = linkPreferences.preferences.followsMovedTabs
        do {
            try family.commit(
                MoveTabToSpace(
                    workspaceID: family.workspaceID, windowID: windowID, spaceID: sourceSpaceID,
                    tabID: id, destinationSpaceID: destinationSpaceID, placement: placement,
                    folderID: folderID, beforeTabID: destinationTabID, follows: follows),
                from: self)
        } catch {
            localSyncErrorDescription = "Core tab move failed: \(error)"
            return false
        }
        if follows {
            pendingMovedTabActivation = BrowserTabRuntimeAssignment(
                tabID: id, spaceID: destinationSpaceID, profileID: destination.profileID)
        }
        return true
    }

    @discardableResult
    func moveTab(
        _ id: UUID,
        matching sourceAssignment: BrowserSpaceRuntimeAssignment,
        into destinationAssignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard
            canMoveTab(
                id,
                matching: sourceAssignment,
                into: destinationAssignment
            )
        else { return false }
        return moveTab(
            id,
            from: sourceAssignment.spaceID,
            into: destinationAssignment.spaceID
        )
    }

    @discardableResult
    func moveTab(
        _ item: BrowserTabDragItem,
        into destinationAssignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        moveTab(
            item.tabID,
            matching: BrowserSpaceRuntimeAssignment(
                spaceID: item.spaceID,
                profileID: item.profileID
            ),
            into: destinationAssignment
        )
    }

    /// Copies a tab among the open tabs, under an identity the core gives it,
    /// and shows the copy. Answers the copy, or nil when the core refused it.
    @discardableResult
    func duplicateTab(_ id: UUID, in spaceID: UUID) -> UUID? {
        sendCopying(
            DuplicateTab(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: spaceID, tabID: id, placement: nil,
                shows: true),
            in: spaceID)?.first?.copyTabID
    }

    @discardableResult
    func duplicateTab(
        _ id: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> UUID? {
        guard spaceModel(matching: assignment)?.tabs.model(id) != nil else { return nil }
        return duplicateTab(id, in: assignment.spaceID)
    }

    @discardableResult
    func duplicateSelectedTab() -> UUID? {
        guard let space = shownSpace, let tab = shownTab else { return nil }
        return duplicateTab(tab.id, in: space.id)
    }

}

// MARK: - Split Groups

extension BrowserStore {
    /// Joins a dragged tab to the split group `targetTabID` belongs to.
    ///
    /// The destination is the item's own Space: a split never spans Spaces, so
    /// a drag that started in another Space is refused outright rather than
    /// quietly relocating the tab first.
    @discardableResult
    func addTabToSplit(
        _ item: BrowserTabDragItem,
        joining targetTabID: UUID,
        at memberIndex: Int?
    ) -> Bool {
        guard item.spaceID == selectedSpaceID, let space = spaceModel(matching: item.spaceAssignment) else {
            return false
        }
        return sendCopying(
            JoinSplit(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: space.id,
                tabID: item.tabID, targetTabID: targetTabID, index: memberIndex),
            in: space.id) != nil
    }

    /// Removal relocates the departing tab past its run, so it goes through the
    /// same selected-Space requirement every other placement move has.
    @discardableResult
    func removeTabFromSplit(
        _ tabID: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard spaceModel(matching: assignment) != nil, selectedSpaceID == assignment.spaceID else { return false }
        return family.send(
            LeaveSplit(workspaceID: family.workspaceID, spaceID: assignment.spaceID, tabID: tabID), from: self)
    }

    /// Drops a card into an explicit slot of its own split run.
    ///
    /// The index is the one the domain clamps, so a drag may hand over whatever
    /// gap the pointer is nearest without checking the ends first.
    @discardableResult
    func moveSplitMember(
        _ tabID: UUID,
        toMemberIndex memberIndex: Int,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard spaceModel(matching: assignment) != nil, selectedSpaceID == assignment.spaceID else { return false }
        return family.send(
            MoveSplitMember(
                workspaceID: family.workspaceID, spaceID: assignment.spaceID, tabID: tabID, index: memberIndex),
            from: self)
    }

    /// Steps a card one or more slots along its run. Selection is untouched:
    /// the card the person is moving is the card they keep looking at.
    @discardableResult
    func moveSplitMember(
        _ tabID: UUID,
        by offset: Int,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard spaceModel(matching: assignment) != nil, selectedSpaceID == assignment.spaceID else { return false }
        return family.send(stepping(tabID, by: offset, in: assignment.spaceID), from: self)
    }

    /// Whether stepping `tabID` `offset` slots would move anything, as the
    /// core answers it, in the Space this window shows.
    ///
    /// One predicate for every surface that offers the move: the menu-bar items,
    /// the iPad chords, and both context menus dim themselves with this.
    func canMoveSplitMember(
        _ tabID: UUID,
        by offset: Int,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard selectedSpaceID == assignment.spaceID, spaceModel(matching: assignment) != nil else { return false }
        return family.canSend(stepping(tabID, by: offset, in: assignment.spaceID), from: self)
    }

    private func stepping(_ tabID: UUID, by offset: Int, in spaceID: UUID) -> StepSplitMember {
        StepSplitMember(workspaceID: family.workspaceID, spaceID: spaceID, tabID: tabID, offset: offset)
    }

    @discardableResult
    func dissolveSplit(
        containing tabID: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = spaceModel(matching: assignment), let groupID = space.tabs.model(tabID)?.splitGroupID else {
            return false
        }
        return family.send(
            DissolveSplit(workspaceID: family.workspaceID, spaceID: space.id, groupID: groupID),
            from: self)
    }

    @discardableResult
    func setSplitGroupTitle(
        _ title: String?,
        groupID: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard spaceModel(matching: assignment) != nil else { return false }
        return family.send(
            NameSplit(
                workspaceID: family.workspaceID, spaceID: assignment.spaceID, groupID: groupID,
                name: title),
            from: self, failure: "Core record command failed")
    }

    @discardableResult
    func setSplitGroupEmojiIcon(
        _ emoji: String?,
        groupID: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard spaceModel(matching: assignment) != nil else { return false }
        return family.send(
            SetSplitIcon(workspaceID: family.workspaceID, spaceID: assignment.spaceID, groupID: groupID, emoji: emoji),
            from: self, failure: "Core record command failed")
    }

    @discardableResult
    func setSplitGroupTint(
        _ tint: BrandColor?,
        groupID: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard spaceModel(matching: assignment) != nil else { return false }
        return family.send(
            TintSplit(
                workspaceID: family.workspaceID, spaceID: assignment.spaceID, groupID: groupID,
                tint: tint),
            from: self, failure: "Core record command failed")
    }

    /// Whether the core would join `tabID` to the split of `targetTabID`: no
    /// Start Page on either side, not already one group, and room for another
    /// card. Asked without committing, so menus reflect the core's own rule.
    private func acceptsSplitJoin(_ tabID: UUID, joining targetTabID: UUID, in spaceID: UUID) -> Bool {
        family.canSend(
            JoinSplit(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: spaceID,
                tabID: tabID, targetTabID: targetTabID, index: nil),
            from: self)
    }

    /// The tab "Split With Next Tab" would add to the split of the tab this
    /// window shows, as the core answers it: the next tab row in the shown
    /// tab's own sidebar list that is in no split, when the core would join it.
    var nextSplitJoinCandidate: UUID? {
        (try? core.query(SplitJoinCandidate(windowID: windowID)))?.tabID
    }

    /// The tabs a swipe reaches back and on from the tab this window shows, as
    /// the core answers it: card by card through a split, then the nearest card
    /// of the next stop of its sidebar, and nothing past either end, so a swipe
    /// never leaves the Space.
    var swipeNeighbors: SwipeNeighborTabs {
        (try? core.query(SwipeNeighbors(windowID: windowID))) ?? SwipeNeighborTabs(previousTabID: nil, nextTabID: nil)
    }

    /// Whether the tab-list menu's "Split with Current Tab" would do anything:
    /// the core accepts joining the menu's subject to the selected tab's group
    /// in the Space this window shows.
    func canSplitTabWithSelectedTab(
        _ tabID: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard spaceModel(matching: assignment) != nil, assignment.spaceID == selectedSpaceID,
            let selectedTabID = selectedTabID(in: assignment.spaceID), tabID != selectedTabID
        else { return false }
        return acceptsSplitJoin(tabID, joining: selectedTabID, in: assignment.spaceID)
    }

    /// "Split with Current Tab": the menu's subject joins the selected tab's
    /// group and takes focus, the same way a dropped tab does.
    @discardableResult
    func splitTabWithSelectedTab(
        _ tabID: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard canSplitTabWithSelectedTab(tabID, matching: assignment),
            let selectedTabID = selectedTabID(in: assignment.spaceID)
        else { return false }
        return addTabToSplit(
            BrowserTabDragItem(
                tabID: tabID,
                spaceID: assignment.spaceID,
                profileID: assignment.profileID
            ),
            joining: selectedTabID,
            at: nil
        )
    }

    /// "Open Link in Split View": the link opens as a new tab beside the tab it
    /// came from, and the two present as one split.
    ///
    /// The core commits the new tab and any durable destination copies together
    /// after validating the complete join.
    @discardableResult
    func openLinkInSplit(
        url: URL,
        joining targetTabID: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> UUID? {
        guard canOpenLinkInSplit(joining: targetTabID, matching: assignment) else { return nil }
        let openedID = UUID()
        guard
            sendCopying(
                OpenLinkInSplit(
                    workspaceID: family.workspaceID, windowID: windowID, spaceID: assignment.spaceID,
                    tabID: openedID, targetTabID: targetTabID, address: url.absoluteString,
                    title: url.host() ?? url.absoluteString),
                in: assignment.spaceID) != nil
        else { return nil }
        return openedID
    }

    /// Whether "Open Link in Split View" applies to the card presenting
    /// `tabID`.
    ///
    /// The web-content context menu asks this while AppKit holds the main
    /// thread, so it prepares the core command and releases it without
    /// starting anything: a Start Page is a draft the sidebar does not even
    /// list, and a full group takes no more cards. A refusal omits the item
    /// rather than dimming it — a menu that is rarely relevant reads better
    /// without a permanently disabled row.
    func canOpenLinkInSplit(
        joining tabID: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = spaceModel(matching: assignment), space.id == selectedSpaceID, space.tabs.model(tabID) != nil
        else { return false }
        return family.canSend(
            OpenLinkInSplit(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: space.id, tabID: UUID(),
                targetTabID: tabID, address: "about:blank", title: ""),
            from: self)
    }

    /// Split-level link operations for a page pool. The macOS web-content
    /// context menu asks `canOpenLink` while it is building itself and calls
    /// `openLink` when the person picks the item.
    var splitLinkHost: BrowserSplitLinkHost {
        BrowserSplitLinkHost(
            canOpenLink: { [weak self] tabID, assignment in
                self?.canOpenLinkInSplit(joining: tabID, matching: assignment)
                    ?? false
            },
            openLink: { [weak self] url, tabID, assignment in
                self?.openLinkInSplit(
                    url: url,
                    joining: tabID,
                    matching: assignment
                )
            }
        )
    }
}

// MARK: - Selection

extension BrowserStore {
    /// Shows another Space in this window. What a window shows is the core
    /// device's, and never part of the session.
    func selectSpace(_ id: UUID) {
        guard id != selectedSpaceID, !isDeleting(id), spaceModel(id) != nil else { return }
        selectPresentedSpace(id)
    }

    func selectTab(_ id: UUID) {
        guard let space = shownSpace, activateSessionTab(id, in: space.id) else { return }
    }

    /// Stops showing a tab without closing it: the window returns to the tab
    /// it showed before in the shown Space, or shows nothing there.
    func selectDismissalFallback(afterDismissing id: UUID) {
        guard let space = shownSpace else { return }
        dismissShownTab(id, in: space.id)
    }
}
