import Foundation

extension BrowserStore {
    /// Borrows a Space's profile and policies while keeping browsing records
    /// in a separate, memory-only family. The window starts without a tab. The
    /// core keeps the borrowed Space's settings in step with its owner's and
    /// closes the family's workspace once the owner no longer lends the Space;
    /// whoever closes the window closes the workspace too.
    func makeTemporaryWindowStore(
        in assignment: BrowserSpaceRuntimeAssignment, id: UUID = UUID()
    ) -> BrowserStore? {
        guard spaceModel(matching: assignment) != nil else { return nil }
        let settingsBrowser = profileSettingsBrowser.makeWindowStore(
            BrowserWindowOpening(showingSpaceID: assignment.spaceID, restoresTabs: false))
        let workspaceFamily: BrowserStoreFamily
        do {
            workspaceFamily = try settingsBrowser.family.makeBorrowed(in: assignment, settingsBrowser: settingsBrowser)
        } catch {
            localSyncErrorDescription = "Core workspace creation failed: \(error)"
            return nil
        }
        return BrowserStore(
            opening: BrowserWindowOpening(id: id),
            credentialVault: credentialVault,
            browsingMode: browsingMode,
            family: workspaceFamily,
            linkPreferences: linkPreferences,
            core: core
        )
    }

    /// Settings in a temporary window edit the canonical profile through their
    /// own selection facade. Its native tab still belongs to the workspace.
    var profileSettingsBrowser: BrowserStore { family.temporarySettingsBrowser ?? self }

    /// Whether the core would move the tab to `destination`'s window: a window
    /// over this workspace shows it, and one over a workspace that borrows
    /// this one's Space, or lends its own, takes it.
    func canTransferTab(
        _ id: UUID,
        matching sourceAssignment: BrowserSpaceRuntimeAssignment,
        to destination: BrowserStore,
        in destinationAssignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard sourceAssignment == destinationAssignment, spaceModel(matching: sourceAssignment) != nil,
            destination.spaceModel(matching: destinationAssignment) != nil
        else { return false }
        return family.canSend(movingTab(id, in: sourceAssignment, to: destination), from: self)
    }

    /// Moves the tab to `destination`'s window without closing, archiving or
    /// copying it. The scene coordinator moves its matching live page
    /// separately.
    @discardableResult
    func transferTab(
        _ id: UUID,
        matching sourceAssignment: BrowserSpaceRuntimeAssignment,
        to destination: BrowserStore,
        in destinationAssignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard sourceAssignment == destinationAssignment, spaceModel(matching: sourceAssignment) != nil,
            destination.spaceModel(matching: destinationAssignment) != nil
        else { return false }
        do {
            try BrowserStoreFamily.moveTab(
                movingTab(id, in: sourceAssignment, to: destination), from: self, to: destination)
        } catch {
            localSyncErrorDescription = "Core workspace transfer failed: \(error)"
            return false
        }
        if family !== destination.family { tabMultiSelection.clear() }
        return true
    }

    private func movingTab(_ id: UUID, in assignment: BrowserSpaceRuntimeAssignment, to destination: BrowserStore)
        -> MoveTabToWindow
    {
        MoveTabToWindow(
            workspaceID: family.workspaceID, windowID: windowID, spaceID: assignment.spaceID,
            tabID: id, destinationWindowID: destination.windowID)
    }
}
