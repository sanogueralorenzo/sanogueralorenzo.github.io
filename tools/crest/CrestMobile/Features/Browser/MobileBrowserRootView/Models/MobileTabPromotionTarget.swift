import Foundation

/// The sidebar row the page a window shows grows out of.
struct MobileTabPromotionTarget: Equatable {
    // MARK: - Variables

    let tabID: UUID
    let placement: TabPlacement

    // MARK: - Initializers

    init(tabID: UUID, placement: TabPlacement) {
        self.tabID = tabID
        self.placement = placement
    }

    /// The target the shown tab of the read model promotes from: the tab the
    /// window shows, unless it is a Start Page, which has no row.
    @MainActor
    init?(shownTab: TabStateModel) {
        guard !shownTab.isStartPage else { return nil }
        self.init(tabID: shownTab.id, placement: shownTab.placement)
    }
}
