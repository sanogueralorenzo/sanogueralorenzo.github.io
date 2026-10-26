import Foundation

/// A request to show one page of a Space's settings, asking it for `intent`
/// on arrival.
struct BrowserSettingsSpaceRequest: BrowserSettingsRequest {
    // MARK: - Variables

    let tab: BrowserSpaceSettingsTab
    var intent: BrowserSettingsSpaceIntent = .none

    // MARK: - Actions - Route

    @MainActor
    func apply(to tabState: BrowserSettingsTabState, spaceID: UUID?) {
        guard let spaceID else { return }
        tabState.showSpace(spaceID, tab: tab, intent: intent)
    }
}
