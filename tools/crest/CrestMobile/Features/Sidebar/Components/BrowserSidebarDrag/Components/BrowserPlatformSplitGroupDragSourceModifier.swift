import SwiftUI
import UniformTypeIdentifiers

/// The iOS lift for a stacked split-group row.
///
/// Identical in shape to the tab row's mobile source, and for the same reason:
/// the row carries a context menu, and `UIContextMenuInteraction` cancels any
/// competing gesture the moment it claims the touch. Drag-and-drop is the one
/// path the system arbitrates against a context menu — holding still opens the
/// menu, pulling lifts the row.
///
/// The provider stages the shared lift, the drop feed supplies positions, and
/// the native source completes cancellation on every supported iOS version.
struct BrowserPlatformSplitGroupDragSourceModifier: ViewModifier {
    let item: BrowserSplitGroupDragItem
    /// The run this row stands for, used only to draw the lift preview.
    let members: [TabStateModel]
    let favicons: FaviconAssets?
    let placement: TabPlacement
    let folderID: UUID?
    let reorder: BrowserSidebarReorderContext
    var isEnabled = true

    private var section: BrowserSidebarReorderSection {
        .tabs(placement: placement, folderID: folderID)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            draggableContent(content)
        } else {
            content
        }
    }

    private func draggableContent(_ content: Content) -> some View {
        content
            .browserSidebarReorderSource(
                item: .splitGroup(item),
                section: section,
                reorder: reorder,
                registersContainer: false
            )
            .browserMobileDraggable {
                reorder.state.stage(
                    item: .splitGroup(item), section: section, plan: reorder.plan(for: .splitGroup(item)))
                let payload = (try? JSONEncoder().encode(item)) ?? Data()
                let provider = NSItemProvider(
                    item: payload as NSData,
                    typeIdentifier: UTType.json.identifier
                )
                let token = reorder.state.sessionToken
                return BrowserMobileDragSession(provider: provider) {
                    guard let token else { return }
                    reorder.state.cancel(session: token)
                }
            } preview: { _ in
                if let favicons {
                    BrowserSplitGroupDragPreview(
                        members: members,
                        favicons: favicons,
                        profileID: item.profileID
                    )
                }
            }
    }
}
