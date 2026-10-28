import Foundation

/// What shows each kind of stop a numbered selection leads to.
/// `NumberedSelection.select(on:)` calls the one its target names, so a target
/// the core adds fails to compile until the Mac says how it shows it.
@MainActor
protocol BrowserNumberedSelectionPerformer {
    /// Shows the tab `tabID` in the Space `spaceID`.
    func selectTab(_ tabID: UUID?, in spaceID: UUID)

    /// Shows the Space `spaceID`.
    func selectSpace(_ spaceID: UUID)
}
