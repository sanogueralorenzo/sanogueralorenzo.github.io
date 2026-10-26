import Observation

/// Tells every browser window that the sidebar hover area is being adjusted,
/// so each window with a hidden sidebar can show its strip for a moment.
///
/// The strip is invisible on its own; showing it is how the person moving the
/// slider sees what the number means.
@MainActor
@Observable
final class SidebarRevealWidthPreview {
    static let shared = SidebarRevealWidthPreview()

    /// Changes on every adjustment; windows restart their fade when it does.
    private(set) var adjustmentCount = 0

    func adjusted() {
        adjustmentCount += 1
    }
}
