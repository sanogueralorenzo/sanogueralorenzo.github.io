import Foundation

/// Adapted from Crest's BrowserSidebarReorderLayout: a lift removes source
/// intervals and opens one destination interval without editing the session.
struct BrowserSidebarReorderLayout: Equatable {
    struct Section: Equatable {
        let spaceID: UUID
        let placement: BrowserTab.Placement
        let folderID: UUID?
    }

    struct Gap: Equatable {
        let section: Section
        let before: UUID?
        let after: UUID?
        let frame: CGRect
        let containingFolders: Set<UUID>
    }

    var hiddenIDs: Set<UUID> = []
    var removedFrames: [CGRect] = []
    var sourceSpaceID: UUID?
    var gap: Gap?
    var height: CGFloat = 0
    var gridFrame: CGRect?
    var gridHeightDelta: CGFloat = 0
    var dividerFrame: CGRect?
    var dividerHeightDelta: CGFloat = 0

    func topSpace(for id: UUID) -> CGFloat { gap?.before == id ? height : 0 }
    func bottomSpace(for id: UUID) -> CGFloat { gap?.after == id ? height : 0 }
    func emptySpace(in section: Section) -> CGFloat {
        gap?.section == section && gap?.before == nil && gap?.after == nil ? height : 0
    }

    func projected(_ frame: CGRect, in spaceID: UUID, containsGap: Bool = false) -> CGRect {
        func removingSource(at y: CGFloat) -> CGFloat {
            let removal =
                spaceID == sourceSpaceID
                ? removedFrames.reduce(CGFloat.zero) { $0 + min($1.height, max(0, y - $1.minY)) } : 0
            let gridShift = gridFrame.map { y >= $0.maxY - 0.5 ? gridHeightDelta : 0 } ?? 0
            let dividerShift = dividerFrame.map { y >= $0.maxY - 0.5 ? dividerHeightDelta : 0 } ?? 0
            return y - removal + gridShift + dividerShift
        }
        var result = CGRect(
            x: frame.minX, y: removingSource(at: frame.minY), width: frame.width,
            height: max(0, removingSource(at: frame.maxY) - removingSource(at: frame.minY)))
        guard let gap, gap.section.spaceID == spaceID else { return result }
        let gapY = removingSource(at: gap.frame.minY)
        if containsGap { result.size.height += height } else if result.minY >= gapY - 0.5 { result.origin.y += height }
        return result
    }
}

/// Crest's pinned-slot projection, using Lean's existing two-column density.
/// The source stays mounted but does not occupy a slot while it travels.
struct BrowserPinnedTabReorderLayout: Equatable {
    let ids: [UUID]
    var liftedIDs: Set<UUID> = []
    var insertionIndex: Int?
    var availableWidth: CGFloat
    static let spacing: CGFloat = 8

    var slots: [UUID?] {
        var result = ids.filter { !liftedIDs.contains($0) }.map(Optional.some)
        if let insertionIndex { result.insert(nil, at: min(max(0, insertionIndex), result.count)) }
        return result
    }
    var columns: Int { max(1, min(2, slots.count)) }
    var height: CGFloat {
        let rows = (slots.count + columns - 1) / columns
        return rows == 0 ? 0 : CGFloat(rows) * SidebarGeometry.rowHeight + CGFloat(rows - 1) * Self.spacing
    }
    func frame(for id: UUID?, in bounds: CGRect) -> CGRect? {
        guard let index = slots.firstIndex(where: { $0 == id }) else { return nil }
        let width = max(0, (bounds.width - CGFloat(columns - 1) * Self.spacing) / CGFloat(columns))
        return CGRect(
            x: bounds.minX + CGFloat(index % columns) * (width + Self.spacing),
            y: bounds.minY + CGFloat(index / columns) * (SidebarGeometry.rowHeight + Self.spacing),
            width: width, height: SidebarGeometry.rowHeight)
    }
}
