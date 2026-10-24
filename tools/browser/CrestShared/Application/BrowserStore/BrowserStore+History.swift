import Foundation

// MARK: - History and Cleanup

extension BrowserStore {
    /// Keeps a Quick Window's page, `pageID`, in the archive of the Space it
    /// lived in, at the address and title the core holds for it, and answers
    /// whether the core kept it. The page may already be gone, as one memory
    /// pressure took back is; the core keeps what it showed last.
    @discardableResult
    func archiveTransientPage(_ pageID: UUID, matching assignment: BrowserSpaceRuntimeAssignment) -> Bool {
        let archive = ArchiveTransientPage(workspaceID: family.workspaceID, pageID: pageID, spaceID: assignment.spaceID)
        // The core archives a page once, and never one kept as a tab.
        guard spaceModel(matching: assignment) != nil, family.canSend(archive, from: self) else { return false }
        return family.perform(archive, from: self) != nil
    }

    func clearHistory() {
        guard shownSpace != nil else { return }
        clearHistory(in: selectedSpaceID)
    }

    func clearHistory(in spaceID: UUID) {
        sendRecords(ClearHistory(workspaceID: family.workspaceID, spaceID: spaceID))
    }

    @discardableResult
    func clearHistory(
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard spaceModel(matching: assignment) != nil else { return false }
        return sendRecords(ClearHistory(workspaceID: family.workspaceID, spaceID: assignment.spaceID))
    }

    /// Removes `address` from a Space's history, every visit to it.
    @discardableResult
    func removeHistoryAddress(_ address: String, in spaceID: UUID) -> Bool {
        sendRecords(RemoveHistoryAddress(workspaceID: family.workspaceID, spaceID: spaceID, address: address))
    }

    func cleanupCurrentTabs() {
        sendRecords(CleanUpCurrentTabs(workspaceID: family.workspaceID, spaceID: nil))
    }

    /// Applies every Space's tab and stored-record retention policies to a
    /// session that is already running, rather than only at launch. Windows
    /// share one session, and the core sweeps it at most once a minute unless
    /// a Space's retention changed, so every window may ask whenever it
    /// becomes active. A sweep that expires nothing changes nothing.
    func sweepExpiredBrowsingData() {
        sendRecords(SweepExpiredRecords(workspaceID: family.workspaceID))
    }

    /// Sweeps once for the scene that just became active, then keeps sweeping on
    /// `BrowserCurrentTabCleanupSchedule.sweepInterval`.
    ///
    /// The caller owns the lifetime: a scene ties this to being active, so the
    /// loop is cancelled — and the sweep suspends — as soon as the scene stops
    /// being active. Every pass runs on the main actor, so windows serialize.
    func sweepExpiredBrowsingDataWhileSceneIsActive(
        additionalSweep: @MainActor () -> Void = {}
    ) async {
        sweepExpiredBrowsingData()
        additionalSweep()
        while !Task.isCancelled {
            do {
                try await Task.sleep(
                    for: .seconds(BrowserCurrentTabCleanupSchedule.sweepInterval)
                )
            } catch {
                return
            }
            sweepExpiredBrowsingData()
            additionalSweep()
        }
    }

    func cleanupCurrentTabs(in spaceID: UUID) {
        guard spaceModel(spaceID) != nil else { return }
        sendRecords(CleanUpCurrentTabs(workspaceID: family.workspaceID, spaceID: spaceID))
    }

    func restoreArchivedTab(_ id: UUID) {
        guard shownSpace != nil else { return }
        sendRecords(
            RestoreArchivedTab(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: selectedSpaceID,
                tabID: id))
    }

    @discardableResult
    func restoreArchivedTab(
        _ id: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = spaceModel(matching: assignment),
            selectedSpaceID == assignment.spaceID,
            space.archive.contains(tabID: id)
        else { return false }
        return sendRecords(
            RestoreArchivedTab(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: assignment.spaceID,
                tabID: id))
    }

    /// Reopens the tab the Space this window shows archived last, which the
    /// core chooses, and shows it here. False when it keeps none.
    @discardableResult
    func reopenClosedTab() -> Bool {
        guard let space = shownSpace else { return false }
        return sendRecords(ReopenClosedTab(workspaceID: family.workspaceID, windowID: windowID, spaceID: space.id))
    }

    /// Runs a history, archive or retention intent from this window, and
    /// answers whether it changed the session.
    @discardableResult
    private func sendRecords(_ intent: some Intent) -> Bool {
        family.send(intent, from: self, failure: "Core record command failed")
    }
}

// MARK: - Data Retention

extension BrowserStore {
    /// Sets how long a Space keeps what it browses. The core sweeps the Space
    /// under the new retention as it accepts it, so a changed retention is
    /// never held back by the last sweep.
    func updateDataRetentionPreferences(
        _ retention: DataRetentionPreferences,
        in spaceID: UUID
    ) {
        guard var preferences = spaceModel(spaceID)?.settings.browsingPreferences,
            preferences.dataRetention != retention
        else {
            return
        }
        preferences.dataRetention = retention
        updateBrowsingPreferences(preferences, in: spaceID)
    }
}
