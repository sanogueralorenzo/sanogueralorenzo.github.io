import SwiftUI

/// The Space strip every sidebar is built around, and the one thing to show
/// when there are no Spaces to strip.
///
/// Both shells wire the pager the same way — the same Spaces, the same
/// selection, the same lock while a drag is in flight — and differ only in the
/// page they draw inside it and the chrome they wrap around it. So the wiring
/// lives here and the page arrives as a builder.
struct BrowserSidebarSpacePager<Page: View>: View {
    let context: BrowserSidebarContext
    @ViewBuilder let page: (SpaceModel, Bool) -> Page

    @State private var dropViewportID = UUID()

    var body: some View {
        if context.availableSpaces.isEmpty {
            ContentUnavailableView("No Spaces", systemImage: "square.grid.2x2")
        } else {
            BrowserSpacePager(
                spaces: context.availableSpaces,
                selectedSpaceID: context.browser.selectedSpaceID,
                isInteractionLocked: isInteractionLocked,
                spaceStep: context.browser.spaceStep,
                selectSpace: { spaceID in
                    context.selectSpace(spaceID)
                    return context.browser.selectedSpaceID
                },
                content: { space, isSelected in
                    page(space, isSelected)
                        .environment(\.browserSidebarDropViewportID, dropViewportID)
                }
            )
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: BrowserSidebarReorderSpace.globalSpace)
            } action: { frame in
                context.sidebarInteraction.sidebarReorderState.register(sidebarViewport: frame, for: dropViewportID)
            }
            .onDisappear {
                context.sidebarInteraction.sidebarReorderState.removeSidebarViewport(for: dropViewportID)
            }
        }
    }

    /// A drag in flight owns the horizontal axis: paging under it would move
    /// the rows the drop is aimed at.
    ///
    /// The reorder state counts first, and used not to. The two drag states
    /// answer for the pointer path, which is the only lift macOS had when this
    /// lock was written; a touch lift runs entirely through the reorder state
    /// and leaves both of them nil, so the pager stayed live under it. Dragging
    /// a row to the edge of a touch shell then paged the strip and changed
    /// Space mid-lift — a move no lifted tab can make, and one that swaps the
    /// rows its drop was aimed at for another Space's.
    private var isInteractionLocked: Bool {
        context.sidebarInteraction.ownsHorizontalAxis
    }
}
