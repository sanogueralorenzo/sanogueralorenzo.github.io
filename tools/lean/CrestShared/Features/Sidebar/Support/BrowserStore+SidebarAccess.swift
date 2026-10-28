extension BrowserStore {
    // MARK: - Variables

    var availableSpaces: [SpaceModel] {
        spaceModels.filter { !isDeleting($0.id) }
    }

    // MARK: - Actions - Space Access

    func availableSpace(
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> SpaceModel? {
        guard !isDeleting(assignment.spaceID), let space = spaceModel(assignment.spaceID),
            space.profileID == assignment.profileID
        else { return nil }
        return space
    }

    func selectedAvailableSpace(
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> SpaceModel? {
        guard selectedSpaceID == assignment.spaceID else { return nil }
        return availableSpace(matching: assignment)
    }

    func showsSelectedSpaceActions() -> Bool {
        shownSpace != nil
    }

    func availableTabMoveDestinationSpaces(
        from sourceAssignment: BrowserSpaceRuntimeAssignment
    ) -> [SpaceModel] {
        guard selectedAvailableSpace(matching: sourceAssignment) != nil
        else { return [] }
        return availableSpaces.filter { space in
            space.id != sourceAssignment.spaceID
        }
    }
}
