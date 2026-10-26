import SwiftUI
import UniformTypeIdentifiers

struct BrowserPlatformFolderDragSourceModifier: ViewModifier {
    let folder: FolderStateModel
    let profileID: UUID
    let spaceID: UUID
    let dragState: BrowserFolderDragState
    var memberTabIDs: [UUID]? = nil
    var reorder: BrowserSidebarReorderContext?
    var isEnabled = true

    @State private var sessionToken: BrowserDragSessionToken?
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if !isEnabled {
            content
        } else if let reorder {
            // As with tabs: the lift comes from drag-and-drop so it can coexist
            // with the row's context menu.
            let item = BrowserFolderDragItem(
                folderID: folder.id,
                spaceID: spaceID,
                profileID: profileID,
                memberTabIDs: memberTabIDs
            )
            content
                .browserSidebarReorderSource(
                    item: .folder(item),
                    section: folder.reorderSection,
                    reorder: reorder,
                    registersContainer: false
                )
                .browserMobileDraggable {
                    reorder.state.stage(
                        item: .folder(item),
                        section: folder.reorderSection,
                        plan: reorder.plan(for: .folder(item))
                    )
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
                    BrowserFolderDragPreview(
                        folder: folder,
                        favicons: reorder.browser.core.state.favicons,
                        sourceHeight: reorder.state.frame(ofRow: .folder(folder.id))?.height
                            ?? BrowserFolderDragPreviewLayout.height,
                        rows: reorder.browser.spaceModel(spaceID).map {
                            BrowserFolderDragPreviewRow.resolve(
                                reorder.state.folderPreviewRows(for: .folder(item)),
                                in: $0, rootFolderID: folder.id)
                        } ?? [],
                        profileID: profileID
                    )
                    .environment(\.colorScheme, colorScheme)
                }
        } else {
            legacyDraggable(content)
        }
    }

    @ViewBuilder
    private func legacyDraggable(_ content: Content) -> some View {
        let draggableContent =
            content
            .onDrag {
                let item = BrowserFolderDragItem(
                    folderID: folder.id,
                    spaceID: spaceID,
                    profileID: profileID,
                    memberTabIDs: memberTabIDs
                )
                sessionToken = dragState.begin(item: item)
                let data = (try? JSONEncoder().encode(item)) ?? Data()
                return NSItemProvider(
                    item: data as NSData,
                    typeIdentifier: UTType.json.identifier
                )
            } preview: {
                BrowserFolderDragPreview(folder: folder)
                    .environment(\.colorScheme, colorScheme)
            }

        draggableContent.endingSidebarDrag({ sessionToken }, in: dragState)
    }
}
