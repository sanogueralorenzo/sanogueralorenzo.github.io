import CoreGraphics
import Foundation

/// The real thing a floating lift is showing, resolved out of the Space.
///
/// The drag carries identifiers; a preview shows titles and favicons. Resolving
/// once, where the Space is already in hand, keeps the preview window a
/// presentation of the drag rather than a second place that has to look things
/// up — and keeps the three kinds of lift the sidebar can start from turning
/// into three kinds of art without anything downstream branching on drag state.
/// The objects are the read model's, so the art redraws as they change.
enum BrowserSidebarLiftPreviewSubject: Equatable {
    case tab(TabStateModel)
    case folder(FolderStateModel, rows: [BrowserFolderDragPreviewRow])
    /// A whole split group, in member order.
    case splitGroup([TabStateModel])
    case selection([BrowserSidebarSelectionPreviewRow])

    // MARK: - Variables

    /// How this kind of subject's art is laid out.
    private var layout: any BrowserSidebarLiftPreviewLayout {
        switch self {
        case .tab: BrowserSidebarTabLiftPreviewLayout()
        case .folder: BrowserSidebarFolderLiftPreviewLayout()
        case .splitGroup(let members): BrowserSidebarSplitLiftPreviewLayout(memberCount: members.count)
        case .selection(let rows): BrowserSidebarSelectionLiftPreviewLayout(rows: rows)
        }
    }

    // MARK: - Actions - Layout

    /// The size the subject's art is laid out at for `lift`, before any
    /// scaling: a tab takes the shape it is morphing into, and every other
    /// subject the width of a folder row and the height of its source.
    func artSize(of lift: BrowserSidebarFloatingLift, rowWidth: CGFloat, pinnedSize: CGSize) -> CGSize {
        layout.artSize(of: lift, rowWidth: rowWidth, pinnedSize: pinnedSize)
    }

    /// The point of the art that stays under the pointer: where a selection
    /// was grabbed, or the lift's anchor in any other art of `artSize`.
    func displayAnchor(of lift: BrowserSidebarFloatingLift, artSize: CGSize) -> CGSize {
        layout.displayAnchor(of: lift, artSize: artSize)
    }

    /// How much the art of `artSize` is scaled: a selection never, any other
    /// art to fill `landedFrame` once it lands, and by the lift's rise while
    /// it is held.
    func scale(artSize: CGSize, landedFrame: CGRect?, reduceMotion: Bool) -> CGSize {
        layout.scale(artSize: artSize, landedFrame: landedFrame, reduceMotion: reduceMotion)
    }

    /// Where the art of `lift` is drawn once it lands in `landedFrame`: a
    /// selection keeps its grab on the lead row of its gathered stack, and
    /// any other art its anchor.
    func landedPointer(of lift: BrowserSidebarFloatingLift, in landedFrame: CGRect, pinnedSize: CGSize) -> CGPoint {
        layout.landedPointer(of: lift, in: landedFrame, pinnedSize: pinnedSize)
    }

    /// The extent the preview window covers for the subject of `lift`, grown
    /// from `base`, the envelope of every shape a lifted row takes: a
    /// selection by its rows both where they were and gathered under the
    /// grab, and a split by its member lines.
    func drawingExtent(from base: CGSize, of lift: BrowserSidebarFloatingLift) -> CGSize {
        layout.drawingExtent(from: base, of: lift)
    }

    // MARK: - Actions - Equality

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.tab(let tab), .tab(let other)): tab === other
        case (.folder(let folder, let rows), .folder(let other, let otherRows)):
            folder === other && rows.map(\.id) == otherRows.map(\.id) && rows.map(\.frame) == otherRows.map(\.frame)
        case (.splitGroup(let members), .splitGroup(let others)): members.elementsEqual(others, by: ===)
        case (.selection(let rows), .selection(let others)): rows == others
        default: false
        }
    }
}

struct BrowserSidebarSelectionPreviewRow: Equatable, Identifiable {
    // MARK: - Variables

    let id: BrowserSidebarReorderItemID
    let tabs: [TabStateModel]
    let frame: CGRect
    var folder: FolderStateModel? = nil
    var folderRows: [BrowserFolderDragPreviewRow] = []
    var isSplit: Bool {
        if case .splitGroup = id { return true }
        return false
    }

    // MARK: - Actions - Resolving

    @MainActor
    static func resolve(
        _ rows: [BrowserSidebarReorderRow], in space: SpaceModel,
        folderRows: (UUID) -> [BrowserSidebarReorderRow]
    ) -> [Self] {
        rows.compactMap { row in row.id.selectionPreviewRow(at: row.frame, in: space, folderRows: folderRows) }
    }

    // MARK: - Actions - Stacking

    /// How far down the gathered stack of `rows` the row `id` starts, each
    /// row before it taking its height in the stack for a lift of `shape`.
    static func stackOffset(
        of id: BrowserSidebarReorderItemID, in rows: [Self], shape: BrowserTabDragPreviewShape, pinnedSize: CGSize
    ) -> CGFloat {
        rows.prefix { $0.id != id }.reduce(0) { $0 + $1.stackHeight(shape: shape, pinnedSize: pinnedSize) }
    }

    /// The row's height in a gathered stack for a lift of `shape`: a split or
    /// folder keeps its own, and a tab takes a row's or a tile's.
    func stackHeight(shape: BrowserTabDragPreviewShape, pinnedSize: CGSize) -> CGFloat {
        if isSplit || folder != nil { return frame.height }
        return shape == .pinnedTile ? pinnedSize.height : BrowserTabDragPreviewLayout.rowSize.height
    }

    // MARK: - Actions - Equality

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.frame == rhs.frame && lhs.tabs.elementsEqual(rhs.tabs, by: ===)
            && lhs.folder === rhs.folder && lhs.folderRows.map(\.id) == rhs.folderRows.map(\.id)
    }
}

extension BrowserSidebarReorderItemID {
    /// The selection preview row this row of `space`, measured at `frame`,
    /// shows: its tab, its split's members, or its folder with the rows
    /// `folderRows` measures inside it; nil once the Space no longer holds it.
    @MainActor
    func selectionPreviewRow(
        at frame: CGRect, in space: SpaceModel, folderRows: (UUID) -> [BrowserSidebarReorderRow]
    ) -> BrowserSidebarSelectionPreviewRow? {
        let tabs: [TabStateModel]
        switch self {
        case .tab(let id): tabs = space.tabs.model(id).map { [$0] } ?? []
        case .splitGroup(let id): tabs = space.splitMembers(of: id)
        case .folder(let id):
            guard let folder = space.folders.model(id) else { return nil }
            return BrowserSidebarSelectionPreviewRow(
                id: self, tabs: [], frame: frame, folder: folder,
                folderRows: BrowserFolderDragPreviewRow.resolve(folderRows(id), in: space, rootFolderID: id))
        }
        guard !tabs.isEmpty else { return nil }
        return BrowserSidebarSelectionPreviewRow(id: self, tabs: tabs, frame: frame)
    }
}

extension BrowserSidebarReorderItem {
    /// What the floating lift of this row alone shows, resolved in `space`:
    /// the tab, the folder with `previewRows`, the rows measured inside it,
    /// or the split's members; nil once the Space no longer holds it. A run
    /// that has already lost its members has nothing to draw; the drag itself
    /// is ended by the same change.
    @MainActor
    func liftPreviewSubject(
        in space: SpaceModel, previewRows: [BrowserSidebarReorderRow]
    ) -> BrowserSidebarLiftPreviewSubject? {
        dragged.liftPreviewSubject(in: space, previewRows: previewRows)
    }
}
