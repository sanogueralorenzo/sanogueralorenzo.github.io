import Foundation

/// A request to show a settings destination.
struct BrowserSettingsDestinationRequest: BrowserSettingsRequest {
    // MARK: - Variables

    let destination: BrowserSettingsDestination

    // MARK: - Actions - Route

    @MainActor
    func apply(to tabState: BrowserSettingsTabState, spaceID: UUID?) {
        tabState.navigation.selection = .destination(destination)
    }
}
