import CoreGraphics
import Foundation

/// One lift aimed at the sidebar: the pointer against the lift's projected rows
/// and the visible drop zones, which together say where it would land.
@MainActor
struct BrowserSidebarReorderAim {
    let lift: BrowserSidebarReorderState.Lift
    let pointer: CGPoint
    let insertionPoint: CGPoint
    let layout: BrowserSidebarReorderLayout
    let pinned: (layout: BrowserPinnedTabReorderLayout, frame: CGRect, emptyHeight: CGFloat)?
    let zones: [BrowserSidebarReorderZone]
    let rows: [BrowserSidebarReorderItemID: BrowserSidebarReorderGeometry.RegisteredRow]
    let splitCards: [UUID: BrowserSidebarReorderGeometry.SplitCard]

    func target(previousTarget: BrowserSidebarReorderTarget?) -> BrowserSidebarReorderTarget? {
        let available = zones.filter { !$0.frame.isEmpty && allowsNesting(in: $0) }
        let direct = BrowserSidebarReorderZone.aimed(
            at: pointer, in: available, accepting: lift.item, plan: lift.plan)
        if let direct, direct.target.outranksGap { return direct.target.reorderTarget(for: self) }
        // Keep the open gap stable while neighbouring rows animate around it.
        if let gap = layout.gapFrame, gap.contains(insertionPoint) { return previousTarget }
        if let pinned, let gap = pinned.layout.frame(for: .gap, in: pinned.frame), gap.contains(pointer) {
            return previousTarget
        }
        let nesting = direct.flatMap { $0.target.nests ? $0 : nil }
        guard
            let zone = nesting
                ?? BrowserSidebarReorderZone.aimed(
                    at: insertionPoint, in: available, accepting: lift.item, plan: lift.plan)
        else { return nil }
        return zone.target.reorderTarget(for: self)
    }

    /// Where a lift aimed at the run `section` inserts, among its rows the
    /// lift does not carry.
    func insertionTarget(in section: BrowserSidebarReorderSection)
        -> BrowserSidebarReorderTarget?
    {
        if section == lift.section, let parentID = rows[lift.item.id]?.row.parentItemID,
            let parent = rows[parentID]?.row, layout.frame(for: parent)?.contains(pointer) == true
        {
            return nil
        }
        let ordered = section.rows(
            from: rows.values.map(\.row).filter { $0.space == lift.item.spaceAssignment && $0.parentItemID == nil }
                .compactMap {
                    row in
                    let frame: CGRect?
                    if row.usesGridOrdering, let pinned {
                        frame = pinned.layout.frame(for: .tab(row.id), in: pinned.frame)
                    } else {
                        frame = layout.frame(for: row)
                    }
                    guard let frame else { return nil }
                    return BrowserSidebarReorderRow(
                        id: row.id, space: row.space, section: row.section, frame: frame)
                })
        let candidates = ordered.filter { !lift.item.selectionRowIDs.contains($0.id) }
        let index = BrowserSidebarReorderRow.insertionIndex(
            at: insertionPoint, orderedRows: candidates, excluding: lift.item.id)
        let anchor = BrowserSidebarReorderRow.insertionAnchor(
            index: index, orderedRows: candidates, excluding: lift.item.id)
        return BrowserSidebarReorderTarget(
            kind: .insert(section: section, beforeID: anchor, index: index))
    }

    /// Horizontal movement admits deeper folder sections; vertical motion stays among siblings.
    private func allowsNesting(in zone: BrowserSidebarReorderZone) -> Bool {
        guard case .folder = lift.item, case .section(let section) = zone.target else { return true }
        let startX = layout.sourceFrame.minX + lift.grabOffset.width
        let extraDepth = max(0, Int((pointer.x - startX) / BrowserFolderLayout.nestingIndent))
        return folderDepth(of: section) <= folderDepth(of: lift.section) + extraDepth
    }

    private func folderDepth(of section: BrowserSidebarReorderSection) -> Int {
        var ancestors: Set<UUID> = []
        var parent = section.parentFolderID
        while let id = parent, ancestors.insert(id).inserted {
            parent = rows[.folder(id)]?.row.section.parentFolderID
        }
        return ancestors.count
    }

    /// Where a lift aimed at the content area for `assignment` joins the
    /// cards on show, or nil when none are measured.
    func splitInsertTarget(in assignment: BrowserSpaceRuntimeAssignment)
        -> BrowserSidebarReorderTarget?
    {
        // Departing Space cards may remain registered until their transition finishes.
        let cards = splitCards.filter { $0.value.space == assignment && !$0.value.frame.isEmpty }
        guard !cards.isEmpty else { return nil }
        return BrowserSidebarReorderTarget(
            kind: .splitInsert(
                assignment: assignment,
                index: BrowserSplitColumnLayout.insertionIndex(
                    at: pointer,
                    orderedCardFrames: BrowserSplitColumnLayout.orderedCardFrames(cards.values.map(\.frame)))
            ))
    }
}
