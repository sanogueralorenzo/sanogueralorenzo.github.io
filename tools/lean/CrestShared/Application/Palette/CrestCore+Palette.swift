import Foundation

extension CrestCore {
    /// Capture current read models once; matching and ranking never hold the
    /// state core's lock or serialize rows across the language boundary.
    func palette(_ question: PaletteSuggestions) async -> PaletteAnswer? {
        guard let snapshot = paletteSnapshot(question) else { return nil }
        return await Task.detached(priority: .userInitiated) { snapshot.answer(question) }.value
    }

    /// Opening the palette and accepting Tab need an answer in the same event.
    func paletteNow(_ question: PaletteSuggestions) -> PaletteAnswer? {
        paletteSnapshot(question)?.answer(question)
    }

    private func paletteSnapshot(_ question: PaletteSuggestions) -> NativePalette? {
        drain()
        guard let window = state.windows[question.windowID], let workspace = state.workspaces[window.workspaceID] else {
            return nil
        }
        let deleting = Set(workspace.spaceDeletions.map(\.spaceID))
        let available = workspace.spaces.models.filter { !deleting.contains($0.id) }
        let space = available.first { $0.id == window.shownSpaceID }
        let preferences = state.appPreferences
        let resolution = BrowserAddress.resolve(question.text, provider: preferences.searchProvider)
        return NativePalette(
            space: space.map {
                PaletteSpaceSnapshot(folders: $0.folders.values, tabs: $0.tabs.values, history: $0.history.entries)
            }, shownTabID: window.shownTabID(in: window.shownSpaceID),
            isPrivate: workspace.kind.isPrivate,
            spaces: available.filter { $0.id != window.shownSpaceID }.map {
                PaletteSpaceChoice(id: $0.id, name: $0.settings.name)
            }, now: .now,
            provider: preferences.searchProvider, suggests: preferences.searchSuggestionsEnabled, resolution: resolution
        )
    }
}
