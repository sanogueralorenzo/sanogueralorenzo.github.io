import CoreGraphics
import Foundation

/// A visible part of a lifted folder, kept at its measured position.
struct BrowserFolderDragPreviewRow: Identifiable {
    // MARK: - Types

    enum Content {
        case tab(TabStateModel)
        case folder(FolderStateModel, depth: Int)
        case splitGroup([TabStateModel])
    }

    // MARK: - Variables

    let id: BrowserSidebarReorderItemID
    let frame: CGRect
    let content: Content

    /// The height the row takes in the lifted folder's art: a folder header's
    /// own, and any other row its measured one.
    var previewHeight: CGFloat {
        switch content {
        case .folder: BrowserFolderDragPreviewLayout.height
        case .tab, .splitGroup: frame.height
        }
    }

    // MARK: - Actions - Resolving

    /// The rows of the lifted folder `rootFolderID` the reorder registry
    /// measured, with the objects each stands for in `space`.
    @MainActor
    static func resolve(
        _ rows: [BrowserSidebarReorderRow], in space: SpaceModel, rootFolderID: UUID
    ) -> [Self] {
        let rootDepth = depth(of: rootFolderID, in: space)
        return rows.compactMap { row in
            row.id.folderPreviewContent(in: space, rootDepth: rootDepth).map {
                Self(id: row.id, frame: row.frame, content: $0)
            }
        }
    }

    /// How many folders hold the folder.
    @MainActor
    static func depth(of folderID: UUID, in space: SpaceModel) -> Int {
        var depth = 0
        var visited: Set<UUID> = [folderID]
        var parent = space.folders.model(folderID)?.parentID
        while let id = parent, visited.insert(id).inserted {
            depth += 1
            parent = space.folders.model(id)?.parentID
        }
        return depth
    }
}

extension BrowserSidebarReorderItemID {
    /// What this row of `space` shows inside a lifted folder whose own depth
    /// is `rootDepth`: its tab, its folder's header at its depth inside the
    /// lifted one, or its split's members; nil once the Space no longer
    /// holds it.
    @MainActor
    func folderPreviewContent(in space: SpaceModel, rootDepth: Int) -> BrowserFolderDragPreviewRow.Content? {
        switch self {
        case .tab(let id):
            return space.tabs.model(id).map(BrowserFolderDragPreviewRow.Content.tab)
        case .folder(let id):
            return space.folders.model(id).map {
                .folder($0, depth: max(0, BrowserFolderDragPreviewRow.depth(of: id, in: space) - rootDepth))
            }
        case .splitGroup(let id):
            let members = space.splitMembers(of: id)
            return members.isEmpty ? nil : .splitGroup(members)
        }
    }
}
