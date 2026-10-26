extension BrowserStore {
    // MARK: - Actions - Palette Actions

    func isPaletteSourceAvailable(
        _ source: BrowserTabRuntimeAssignment
    ) -> Bool {
        selectedPaletteSource(matching: source) != nil
    }

    func paletteTarget(
        _ target: BrowserTabRuntimeAssignment,
        from source: BrowserTabRuntimeAssignment
    ) -> (space: SpaceModel, tab: TabStateModel)? {
        guard target.spaceID == source.spaceID, target.profileID == source.profileID,
            let (space, _) = selectedPaletteSource(matching: source),
            let tab = space.tabs.model(target.tabID)
        else { return nil }
        return (space, tab)
    }

    private func selectedPaletteSource(
        matching source: BrowserTabRuntimeAssignment
    ) -> (space: SpaceModel, tab: TabStateModel)? {
        guard
            let space = selectedAvailableSpace(
                matching: BrowserSpaceRuntimeAssignment(spaceID: source.spaceID, profileID: source.profileID)),
            selectedTabID(in: space.id) == source.tabID,
            let tab = space.tabs.model(source.tabID)
        else { return nil }
        return (space, tab)
    }
}
