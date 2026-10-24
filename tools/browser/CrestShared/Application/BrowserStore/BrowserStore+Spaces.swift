import Foundation

// MARK: - Spaces and Import

extension BrowserStore {
    /// Composition gives the app's one access controller every store whose
    /// workspace shows Spaces it may unlock, including private browsing. The
    /// core's own records refuse a locked Space whatever the views believe.
    func attachSpaceAccess(_ controller: BrowserSpaceAccessController) {
        controller.attach(self)
    }

    func addSpace() {
        family.send(
            CreateSpace(workspaceID: family.workspaceID, windowID: windowID, spaceID: UUID()), from: self,
            failure: "Core Space command failed")
    }

    /// Deletes a Space in two steps the core saves before each returns: the
    /// deletion begins, the platform erases the profile's data and its
    /// passwords, then the Space goes. A relaunch resumes a deletion that
    /// began, with the operation it recorded. Throws the rule the core applied
    /// or why erasing failed; the Space is then kept.
    func deleteSpace(
        _ id: UUID,
        dataDeleter: any BrowserSpaceDataDeleting
    ) async throws {
        guard let space = spaceModel(id).map(BrowserSpaceRuntimeAssignment.init(space:)) else {
            throw BrowserSpaceDeletionError.missingSpace
        }
        guard family.beginDeletingSpace(id) else {
            throw BrowserSpaceDeletionError.alreadyDeleting
        }
        defer { family.finishDeletingSpace(id) }

        let operationID = workspaceModel?.spaceDeletions.first(where: { $0.spaceID == id })?.id ?? UUID()
        try family.commit(
            BeginDeletingSpace(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: id,
                operationID: operationID),
            from: self)

        try await dataDeleter.deleteData(for: space)
        try await credentialVault.deleteAll(in: id)

        try family.commit(
            FinishDeletingSpace(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: id,
                operationID: operationID),
            from: self)
    }

    func resumePendingSpaceDeletions(dataDeleter: any BrowserSpaceDataDeleting) async {
        var attempted: Set<UUID> = []
        while let intent = (workspaceModel?.spaceDeletions ?? []).first(where: {
            !attempted.contains($0.spaceID) && !family.isActivelyDeletingSpace($0.spaceID)
        }) {
            attempted.insert(intent.spaceID)
            do { try await deleteSpace(intent.spaceID, dataDeleter: dataDeleter) } catch {
                localSyncErrorDescription = "Space cleanup needs another attempt: \(error.localizedDescription)"
            }
        }
    }

    /// Adds `spaces`, as the core read them from a file, after this
    /// workspace's own. Throws the rule the core refused them with.
    func importSpaces(_ spaces: [SpaceState]) throws(Rejection) {
        guard !spaces.isEmpty else { return }
        try family.commit(
            ImportSpaces(workspaceID: family.workspaceID, windowID: windowID, spaces: spaces.map(\.seed)), from: self)
    }

    /// Imports the review setup holds for this workspace, as the person chose.
    /// Throws the rule that refused it.
    func importReviewedSpaces() throws(Rejection) {
        try family.commit(ImportReviewedSpaces(workspaceID: family.workspaceID, windowID: windowID), from: self)
    }

    /// The session importing the review setup holds would leave this
    /// workspace with. Throws the rule that would refuse it.
    func reviewedImportPreview() throws(Rejection) -> BrowserSessionPreview {
        try importPreview(ImportReviewedSpaces(workspaceID: family.workspaceID, windowID: windowID))
    }

    /// The session `intent` would leave this workspace with, wearing the
    /// images each tab would wear. Nothing changes. Throws the rule that
    /// would refuse the import.
    func importPreview(_ intent: some ImportWorkspace) throws(Rejection) -> BrowserSessionPreview {
        BrowserSessionPreview(importing: try core.query(ImportPreview(import: intent)), images: core.state.favicons)
    }

    func updateSpaceIdentity(
        _ spaceID: UUID,
        name: String,
        symbol: String,
        accent: SpaceAccent
    ) {
        sendSpaceSettings(
            SetSpaceIdentity(
                workspaceID: profileSettingsBrowser.family.workspaceID, spaceID: spaceID, name: name,
                symbol: symbol, accent: accent))
    }

    /// The core applies its branding rules to the look before it keeps it.
    func updateSpaceBranding(
        _ branding: SpaceBranding,
        in spaceID: UUID
    ) {
        sendSpaceSettings(
            SetSpaceBranding(
                workspaceID: profileSettingsBrowser.family.workspaceID, spaceID: spaceID,
                branding: branding))
    }

    func setDefaultSpace(_ spaceID: UUID) {
        sendSpaceSettings(
            SetDefaultSpace(workspaceID: profileSettingsBrowser.family.workspaceID, spaceID: spaceID))
    }

    /// Sets who may open a Space through the core, and answers the rule that
    /// refused it, such as the Space being locked, or nil once the core took
    /// it. A refusal is the caller's to show; it is no sync failure.
    @discardableResult
    func updateSpaceAccessPolicy(
        _ accessPolicy: SpaceAccessPolicy,
        in spaceID: UUID
    ) -> Rejection? {
        let owner = profileSettingsBrowser
        do throws(Rejection) {
            try owner.family.commit(
                SetSpaceAccess(workspaceID: owner.family.workspaceID, spaceID: spaceID, policy: accessPolicy),
                from: owner)
            return nil
        } catch {
            return error
        }
    }

    /// Sends an intent about a Space's settings to the workspace that owns
    /// the Space's profile: this one, or the one a borrowed workspace borrows
    /// its Space from. Answers whether the session changed.
    @discardableResult
    func sendSpaceSettings(_ intent: some Intent) -> Bool {
        let owner = profileSettingsBrowser
        return owner.family.send(intent, from: owner, failure: "Core Space command failed")
    }

    func moveSpaces(from source: IndexSet, to destination: Int) {
        var order = spaceModels.map(\.id)
        order.move(fromOffsets: source, toOffset: destination)
        family.send(
            ReorderSpaces(workspaceID: family.workspaceID, spaceIDs: order), from: self,
            failure: "Core Space command failed")
    }

    /// Sets a Space's browsing preferences through the core: when it cleans up
    /// current tabs, how it blocks content and how long it keeps what it
    /// browses, only when they differ from what the read model holds. What the
    /// Space searches with is `setSearch`'s.
    func updateBrowsingPreferences(
        _ preferences: BrowsingPreferences,
        in spaceID: UUID
    ) {
        let owner = profileSettingsBrowser
        guard let current = owner.spaceModel(spaceID)?.settings.browsingPreferences else { return }
        guard
            preferences.currentTabCleanup != current.currentTabCleanup
                || preferences.contentBlocking != current.contentBlocking
                || preferences.dataRetention != current.dataRetention
        else { return }
        sendSpaceSettings(
            SetBrowsingPreferences(
                workspaceID: owner.family.workspaceID, spaceID: spaceID,
                currentTabCleanup: preferences.currentTabCleanup,
                contentBlocking: preferences.contentBlocking, dataRetention: preferences.dataRetention))
    }

    /// Makes a Space search with `provider`, or the device's default search for
    /// nil, and suggest searches as `suggestions` says, or as the default does
    /// for nil.
    func setSearch(_ provider: SearchProvider?, suggestions: Bool?, in spaceID: UUID) {
        let owner = profileSettingsBrowser
        sendSpaceSettings(
            SetSpaceSearch(
                workspaceID: owner.family.workspaceID, spaceID: spaceID, provider: provider?.seed,
                suggestionsEnabled: suggestions))
    }
}

// MARK: - Folders

extension BrowserStore {
    @discardableResult
    func setSavedTabsExpanded(
        _ isExpanded: Bool,
        in spaceID: UUID
    ) -> Bool {
        sendSpaceSettings(
            ExpandSavedTabs(
                workspaceID: profileSettingsBrowser.family.workspaceID, spaceID: spaceID,
                isExpanded: isExpanded))
    }

    @discardableResult
    func setSavedTabsExpanded(
        _ isExpanded: Bool,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard spaceModel(matching: assignment) != nil else { return false }
        return setSavedTabsExpanded(isExpanded, in: assignment.spaceID)
    }

    @discardableResult
    func addFolder(
        title: String = "New Folder",
        color: BrandColor = .folderDefault,
        parentID: UUID? = nil,
        in spaceID: UUID
    ) -> UUID? {
        let folderID = UUID()
        guard
            family.send(
                CreateFolder(
                    workspaceID: family.workspaceID, spaceID: spaceID, folderID: folderID,
                    placement: .saved, parentID: parentID, title: title, color: color, symbol: "folder",
                    tabIDs: [], leavesSplits: false),
                from: self)
        else { return nil }
        return folderID
    }

    /// Whether a folder may be created inside `parentID`. The core answers
    /// with its folder count and depth limits.
    func canAddFolder(inside parentID: UUID, matching assignment: BrowserSpaceRuntimeAssignment) -> Bool {
        guard spaceModel(matching: assignment) != nil else { return false }
        return family.canSend(
            CreateFolder(
                workspaceID: family.workspaceID, spaceID: assignment.spaceID, folderID: UUID(),
                placement: .saved, parentID: parentID, title: nil, color: nil, symbol: nil, tabIDs: [],
                leavesSplits: false),
            from: self)
    }

    @discardableResult
    func addFolder(
        title: String = "New Folder",
        color: BrandColor = .folderDefault,
        parentID: UUID? = nil,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> UUID? {
        guard spaceModel(matching: assignment) != nil else { return nil }
        return addFolder(
            title: title,
            color: color,
            parentID: parentID,
            in: assignment.spaceID
        )
    }

    @discardableResult
    func renameFolder(_ folderID: UUID, in spaceID: UUID, title: String) -> Bool {
        guard renameSessionFolder(folderID, in: spaceID, title: title) else { return false }
        return true
    }

    @discardableResult
    func renameFolder(
        _ folderID: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment,
        title: String
    ) -> Bool {
        guard let space = spaceModel(matching: assignment), space.folders.contains(folderID)
        else { return false }
        return renameFolder(folderID, in: assignment.spaceID, title: title)
    }

    @discardableResult
    func setFolderColor(
        _ folderID: UUID,
        in spaceID: UUID,
        color: BrandColor
    ) -> Bool {
        family.send(
            SetFolderColor(
                workspaceID: family.workspaceID, spaceID: spaceID, folderID: folderID,
                color: color),
            from: self)
    }

    @discardableResult
    func setFolderColor(
        _ folderID: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment,
        color: BrandColor
    ) -> Bool {
        guard let space = spaceModel(matching: assignment), space.folders.contains(folderID)
        else { return false }
        return setFolderColor(
            folderID,
            in: assignment.spaceID,
            color: color
        )
    }

    @discardableResult
    func setFolderSymbol(
        _ folderID: UUID,
        in spaceID: UUID,
        symbol: String
    ) -> Bool {
        family.send(
            SetFolderSymbol(
                workspaceID: family.workspaceID, spaceID: spaceID, folderID: folderID,
                symbol: symbol),
            from: self)
    }

    @discardableResult
    func setFolderSymbol(
        _ folderID: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment,
        symbol: String
    ) -> Bool {
        guard let space = spaceModel(matching: assignment), space.folders.contains(folderID)
        else { return false }
        return setFolderSymbol(
            folderID,
            in: assignment.spaceID,
            symbol: symbol
        )
    }

    @discardableResult
    func setFolderCollapsed(
        _ folderID: UUID,
        in spaceID: UUID,
        isCollapsed: Bool
    ) -> Bool {
        guard
            collapseSessionFolder(
                folderID,
                in: spaceID,
                isCollapsed: isCollapsed
            )
        else { return false }
        return true
    }

    @discardableResult
    func setFolderCollapsed(
        _ folderID: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment,
        isCollapsed: Bool
    ) -> Bool {
        guard let space = spaceModel(matching: assignment), space.folders.contains(folderID)
        else { return false }
        return setFolderCollapsed(
            folderID,
            in: assignment.spaceID,
            isCollapsed: isCollapsed
        )
    }

    /// Whether a folder may move under `parentID`. The core's folder rules
    /// answer (no cycles, the depth limit including the moving subtree).
    func canMoveFolder(
        _ folderID: UUID,
        in spaceID: UUID,
        into parentID: UUID?
    ) -> Bool {
        guard !isDeleting(spaceID) else { return false }
        return family.canSend(
            MoveFolder(
                workspaceID: family.workspaceID, spaceID: spaceID, folderID: folderID, placement: nil,
                parentID: parentID, beforeFolderID: nil, beforeTabID: nil),
            from: self)
    }

    func canMoveFolder(
        _ folderID: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment,
        into parentID: UUID?
    ) -> Bool {
        guard let space = spaceModel(matching: assignment), space.folders.contains(folderID)
        else { return false }
        return canMoveFolder(
            folderID,
            in: assignment.spaceID,
            into: parentID
        )
    }

    @discardableResult
    func moveFolder(
        _ folderID: UUID,
        in spaceID: UUID,
        into parentID: UUID?,
        before siblingID: UUID? = nil
    ) -> Bool {
        guard
            moveSessionFolder(
                folderID,
                in: spaceID,
                into: parentID,
                before: siblingID
            )
        else { return false }
        return true
    }

    @discardableResult
    func moveFolder(
        _ folderID: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment,
        into parentID: UUID?,
        before siblingID: UUID? = nil
    ) -> Bool {
        guard let space = spaceModel(matching: assignment),
            siblingID == nil
                || space.folders.models.contains(where: {
                    $0.id == siblingID && $0.parentID == parentID
                }),
            canMoveFolder(
                folderID,
                matching: assignment,
                into: parentID
            )
        else { return false }
        return moveFolder(
            folderID,
            in: assignment.spaceID,
            into: parentID,
            before: siblingID
        )
    }

    @discardableResult
    func moveFolder(
        _ item: BrowserFolderDragItem,
        matching destinationAssignment: BrowserSpaceRuntimeAssignment,
        into parentID: UUID?,
        before siblingID: UUID? = nil
    ) -> Bool {
        let sourceAssignment = BrowserSpaceRuntimeAssignment(
            spaceID: item.spaceID,
            profileID: item.profileID
        )
        guard sourceAssignment == destinationAssignment else { return false }
        return moveFolder(
            item.folderID,
            matching: destinationAssignment,
            into: parentID,
            before: siblingID
        )
    }

    @discardableResult
    func deleteFolder(_ folderID: UUID, in spaceID: UUID) -> Bool {
        guard deleteSessionFolder(folderID, in: spaceID) else { return false }
        return true
    }

    @discardableResult
    func deleteFolder(
        _ folderID: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = spaceModel(matching: assignment), space.folders.contains(folderID)
        else { return false }
        return deleteFolder(folderID, in: assignment.spaceID)
    }

}
