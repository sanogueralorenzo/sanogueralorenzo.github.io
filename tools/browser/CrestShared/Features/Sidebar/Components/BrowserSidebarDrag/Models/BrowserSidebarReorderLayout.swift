import CoreGraphics
import Foundation

/// A temporary layout for one lift. The session remains unchanged until drop.
/// Removing the source interval and inserting one destination interval moves
/// every following section, including headers and nested folder boundaries.
struct BrowserSidebarReorderLayout: Equatable {
    struct Gap: Equatable {
        enum Anchor: Equatable {
            case before(BrowserSidebarReorderItemID)
            case after(BrowserSidebarReorderItemID)
            case emptySection(BrowserSidebarReorderSection)
        }

        let section: BrowserSidebarReorderSection
        let anchor: Anchor
        /// Position in the resting layout, before removing the source.
        let frame: CGRect
        let containingFolders: Set<UUID>
    }

    var sourceID: BrowserSidebarReorderItemID?
    var sourceFrame: CGRect = .zero
    var hiddenIDs: Set<BrowserSidebarReorderItemID> = []
    var gap: Gap?
    var sourceIsGrid = false
    var gridFrame: CGRect?
    var gridHeightDelta: CGFloat = 0
    var removedFrames: [CGRect] = []
    var batchHeight: CGFloat?

    var gapHeight: CGFloat { batchHeight ?? (sourceIsGrid ? CrestLayout.sidebarRowHeight : height) }

    var isActive: Bool { sourceID != nil }
    var height: CGFloat { sourceFrame.height }

    var gapFrame: CGRect? {
        gap.map {
            CGRect(x: $0.frame.minX, y: removingSource(at: $0.frame.minY), width: $0.frame.width, height: gapHeight)
        }
    }

    func topSpace(for id: BrowserSidebarReorderItemID) -> CGFloat {
        gap?.anchor == .before(id) ? gapHeight : 0
    }

    func bottomSpace(for id: BrowserSidebarReorderItemID) -> CGFloat {
        gap?.anchor == .after(id) ? gapHeight : 0
    }

    func emptySpace(for section: BrowserSidebarReorderSection) -> CGFloat {
        gap?.anchor == .emptySection(section) ? gapHeight : 0
    }

    func frame(for row: BrowserSidebarReorderRow) -> CGRect? {
        guard isActive, !row.usesGridOrdering, sharesColumn(row.frame) else { return row.frame }
        guard !hiddenIDs.contains(row.id) else { return nil }
        let containsGap = row.id.folderID.map { gap?.containingFolders.contains($0) == true } ?? false
        return project(row.frame, containsGap: containsGap)
    }

    func frame(for zone: BrowserSidebarReorderZone) -> CGRect? {
        guard isActive else { return zone.frame }
        return zone.target.frame(zone.frame, in: self)
    }

    /// `frame` as the lift moves what shares its column: the source removed
    /// and the gap opened, with the gap inside it when it `containsGap`.
    func projected(_ frame: CGRect, containsGap: Bool) -> CGRect {
        guard sharesColumn(frame) else { return frame }
        return project(frame, containsGap: containsGap)
    }

    /// Whether the run `section`, measured at `frame`, holds the open gap:
    /// the gap is in it, in a folder inside it, or opens within its frame.
    func holdsGap(_ section: BrowserSidebarReorderSection, at frame: CGRect) -> Bool {
        section == gap?.section
            || section.parentFolderID.map { gap?.containingFolders.contains($0) == true } == true
            || (gap.map { frame.minY < $0.frame.minY && frame.maxY >= $0.frame.minY } ?? false)
    }

    private func sharesColumn(_ frame: CGRect) -> Bool {
        frame.maxX > sourceFrame.minX && frame.minX < sourceFrame.maxX
    }

    private func removingSource(at y: CGFloat) -> CGFloat {
        let intervals = removedFrames.isEmpty ? (sourceIsGrid ? [] : [sourceFrame]) : removedFrames
        let sourceRemoval = intervals.reduce(CGFloat.zero) { $0 + min($1.height, max(0, y - $1.minY)) }
        let gridShift = gridFrame.map { y >= $0.maxY - 0.5 ? gridHeightDelta : 0 } ?? 0
        return y - sourceRemoval + gridShift
    }

    private func project(_ frame: CGRect, containsGap: Bool) -> CGRect {
        var result = CGRect(
            x: frame.minX, y: removingSource(at: frame.minY), width: frame.width,
            height: max(0, removingSource(at: frame.maxY) - removingSource(at: frame.minY)))
        guard let gapFrame else { return result }
        if containsGap {
            result.size.height += gapHeight
        } else if result.minY >= gapFrame.minY - 0.5 {
            result.origin.y += gapHeight
        }
        return result
    }
}
