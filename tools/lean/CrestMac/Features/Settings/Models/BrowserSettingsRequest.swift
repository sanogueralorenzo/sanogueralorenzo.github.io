import Foundation

/// A request from elsewhere in the app to show a Settings page: a settings
/// destination, or one page of a Space's settings. Each request shows its own
/// page, so a Settings tab's whole route is `request.apply(to: tabState, …)`.
protocol BrowserSettingsRequest: Sendable {
    /// Shows the requested page in `tabState`. `spaceID` is the Space the
    /// request was made for, where this window has it.
    @MainActor
    func apply(to tabState: BrowserSettingsTabState, spaceID: UUID?)
}
