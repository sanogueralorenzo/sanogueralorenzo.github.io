import SwiftUI

/// Lets the desktop shell consume a completed lift outside its source window.
/// In-window reordering and mobile input keep using the shared reorder path.
///
/// One window always hands the same handlers, so two values for one window
/// are equal: a window body that runs again leaves the environment below it
/// untouched instead of invalidating every view in the window.
struct BrowserSidebarWindowDrop: Equatable {
    /// The window whose shell handles the drop.
    var windowID: UUID
    var perform: @MainActor (BrowserSidebarFloatingLift) -> Bool
    var didMeasureRow: @MainActor (BrowserSidebarReorderRow) -> Void = { _ in }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.windowID == rhs.windowID
    }
}

extension EnvironmentValues {
    @Entry var browserSidebarWindowDrop: BrowserSidebarWindowDrop? = nil
}
