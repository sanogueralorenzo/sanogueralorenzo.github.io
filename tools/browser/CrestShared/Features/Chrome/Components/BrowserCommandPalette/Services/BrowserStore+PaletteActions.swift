/// Whether a palette or Start Page action still speaks for what the window
/// shows: its source tab must be the one the window shows, in an unlocked
/// Space of the same profile, and its target a tab of that Space.
extension BrowserStore {
    // MARK: - Actions - Palette Actions

    func isPaletteSourceAvailable(
        _ source: BrowserTabRuntimeAssignment,
        accessController: BrowserSpaceAccessController
    ) -> Bool {
        selectedPaletteSource(matching: source, accessController: accessController) != nil
    }

    func paletteTarget(
        _ target: BrowserTabRuntimeAssignment,
        from source: BrowserTabRuntimeAssignment,
        accessController: BrowserSpaceAccessController
    ) -> (space: SpaceModel, tab: TabStateModel)? {
        guard target.spaceID == source.spaceID, target.profileID == source.profileID,
            let (space, _) = selectedPaletteSource(matching: source, accessController: accessController),
            let tab = space.tabs.model(target.tabID)
        else { return nil }
        return (space, tab)
    }

    private func selectedPaletteSource(
        matching source: BrowserTabRuntimeAssignment,
        accessController: BrowserSpaceAccessController
    ) -> (space: SpaceModel, tab: TabStateModel)? {
        guard
            let space = selectedUnlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(spaceID: source.spaceID, profileID: source.profileID),
                accessController: accessController),
            selectedTabID(in: space.id) == source.tabID,
            let tab = space.tabs.model(source.tabID)
        else { return nil }
        return (space, tab)
    }
}
