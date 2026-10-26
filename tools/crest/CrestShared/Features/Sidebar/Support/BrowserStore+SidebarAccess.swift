/// Which Spaces of a window's workspace its chrome may show and act on, read
/// from the core's read model: every Space not being deleted, and of those,
/// the ones this process holds the grant to show.
extension BrowserStore {
    // MARK: - Variables

    var availableSpaces: [SpaceModel] {
        spaceModels.filter { !isDeleting($0.id) }
    }

    // MARK: - Actions - Space Access

    func unlockedSpace(
        matching assignment: BrowserSpaceRuntimeAssignment,
        accessController: BrowserSpaceAccessController
    ) -> SpaceModel? {
        guard !isDeleting(assignment.spaceID), let space = spaceModel(assignment.spaceID),
            space.profileID == assignment.profileID, !accessController.isLocked(space)
        else { return nil }
        return space
    }

    func selectedUnlockedSpace(
        matching assignment: BrowserSpaceRuntimeAssignment,
        accessController: BrowserSpaceAccessController
    ) -> SpaceModel? {
        guard selectedSpaceID == assignment.spaceID else { return nil }
        return unlockedSpace(matching: assignment, accessController: accessController)
    }

    func showsSelectedSpaceActions(accessController: BrowserSpaceAccessController) -> Bool {
        guard let space = shownSpace else { return false }
        return !accessController.isLocked(space)
    }

    func availableTabMoveDestinationSpaces(
        from sourceAssignment: BrowserSpaceRuntimeAssignment,
        accessController: BrowserSpaceAccessController
    ) -> [SpaceModel] {
        guard selectedUnlockedSpace(matching: sourceAssignment, accessController: accessController) != nil
        else { return [] }
        return availableSpaces.filter { space in
            space.id != sourceAssignment.spaceID && !accessController.isLocked(space)
        }
    }
}
