import Foundation

/// One row of the Settings sidebar: a settings page, or a Space's page.
///
/// The item is the sidebar list's selection and the shown page's identity, so
/// it stays one hashable value. Each case says which row shows it and what
/// choosing it does.
enum BrowserSettingsSidebarItem: Hashable {
    case destination(BrowserSettingsDestination)
    case space(UUID)

    // MARK: - Variables

    /// The row that shows the item. A page without a row selects the row it
    /// lives under.
    var row: BrowserSettingsSidebarItem {
        switch self {
        case .destination(let destination):
            .destination(BrowserPlatformSettingsDestinationCatalog.parent(of: destination) ?? destination)
        case .space:
            self
        }
    }

    // MARK: - Actions - Selection

    /// Chooses the item from the sidebar: a page shows in `tabState`; a Space
    /// opens through `openSpace`.
    @MainActor
    func select(on tabState: BrowserSettingsTabState, openSpace: (UUID) -> Void) {
        switch self {
        case .destination:
            tabState.navigation.selection = self
        case .space(let id):
            // Arranging drags rows; a press that starts a drag isn't a choice.
            guard !tabState.isArrangingSpaces else { return }
            openSpace(id)
        }
    }
}
