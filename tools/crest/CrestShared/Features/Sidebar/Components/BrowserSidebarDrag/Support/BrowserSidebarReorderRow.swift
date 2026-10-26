import CoreGraphics

/// A measured reorderable row. Frames are reported in global coordinates so rows
/// in different branches of the sidebar can be compared against one pointer.
struct BrowserSidebarReorderRow: Equatable, Sendable {
    // MARK: - Variables

    let id: BrowserSidebarReorderItemID

    /// The Space whose run this row stands in.
    ///
    /// A section says only which run it is — `.tabs(placement: .pinned, …)` is
    /// *a* pinned grid, not whose. One reorder state serves every sidebar its
    /// store puts on screen, and more than one of them registers rows at a
    /// time: macOS opens several windows onto the same session, and every
    /// sidebar's Space pager keeps the pages either side of the visible one
    /// alive so a swipe can already show them. Rows from all of those land in
    /// one registry.
    ///
    /// Without the Space they land indistinguishably, and a drag then orders
    /// itself among rows nobody is dragging: insertion counts a neighbouring
    /// Space's tiles as already passed, and the pinned cap counts them as
    /// already filled — which is a grid that silently refuses every incoming
    /// pin while looking half empty.
    let space: BrowserSpaceRuntimeAssignment

    let section: BrowserSidebarReorderSection
    let frame: CGRect
    /// Member frames can start a lift; their container remains the insertion slot.
    var parentItemID: BrowserSidebarReorderItemID? = nil

    var usesGridOrdering: Bool {
        section.usesGridOrdering
    }

    // MARK: - Actions - Ordering

    /// Index the dragged item would occupy within `orderedRows`, excluding
    /// itself. Lists compare against row midpoints; the pinned grid compares
    /// against cell centers so a sideways drag reorders within a row.
    static func insertionIndex(
        at point: CGPoint,
        orderedRows: [BrowserSidebarReorderRow],
        excluding draggedID: BrowserSidebarReorderItemID?
    ) -> Int {
        let candidates = orderedRows.filter { $0.id != draggedID }
        var index = 0
        for row in candidates {
            guard row.isPassed(by: point) else { break }
            index += 1
        }
        return index
    }

    /// The row the dragged item should be inserted before, or `nil` to append.
    static func insertionAnchor(
        index: Int,
        orderedRows: [BrowserSidebarReorderRow],
        excluding draggedID: BrowserSidebarReorderItemID?
    ) -> BrowserSidebarReorderItemID? {
        let candidates = orderedRows.filter { $0.id != draggedID }
        guard index < candidates.count else { return nil }
        return candidates[index].id
    }

    /// Reading order: down the list, and left-to-right within a grid row.
    func precedes(_ other: BrowserSidebarReorderRow) -> Bool {
        let lhsY = frame.minY
        let rhsY = other.frame.minY
        if usesGridOrdering, lhsY == rhsY {
            return frame.minX < other.frame.minX
        }
        return lhsY < rhsY
    }

    /// Whether the pointer has moved beyond this row in reading order.
    ///
    /// A grid cell is only compared horizontally once the pointer is on that
    /// cell's own line; comparing against its center on both axes at once would
    /// treat every cell on the line as passed as soon as the pointer dipped
    /// below the line's middle, which makes leftward moves impossible.
    private func isPassed(by point: CGPoint) -> Bool {
        guard usesGridOrdering else {
            return point.y > frame.midY
        }
        if point.y > frame.maxY { return true }
        if point.y < frame.minY { return false }
        return point.x > frame.midX
    }
}
