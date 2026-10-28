import SwiftUI

/// Crest's source/gap treatment, attached to the whole item rather than only
/// its drag handle so expanded folders and split groups travel as one block.
struct BrowserSidebarReorderItem: ViewModifier {
    let store: BrowserStore
    let id: UUID
    let placement: BrowserTab.Placement
    let folderID: UUID?
    var parentItemID: UUID?
    @State private var identity = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var state: BrowserSidebarReorderState { store.sidebarReorder }
    private var hidden: Bool { state.hides(id) || store.owner.sidebarDrag.landingIDs.contains(id) }
    private var lifted: Bool { state.hides(id) && placement != .pinned }

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            BrowserSidebarReorderGap(height: state.layout.topSpace(for: id))
            content
                .frame(height: lifted ? state.frame(of: id)?.height : nil, alignment: .top)
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global)
                } action: { frame in
                    guard frame.height > 0 else { return }
                    state.register(
                        .init(
                            id: id,
                            section: .init(spaceID: store.activeSpace.id, placement: placement, folderID: folderID),
                            parentItemID: parentItemID ?? folderID, frame: frame), owner: identity)
                }
                .onDisappear { state.removeRow(id, owner: identity) }
                .opacity(hidden ? 0 : 1)
                .animation(nil, value: state.hides(id))
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.10),
                    value: store.owner.sidebarDrag.landingIDs.contains(id)
                )
                .frame(height: lifted ? 0 : nil, alignment: .top)
            BrowserSidebarReorderGap(height: state.layout.bottomSpace(for: id))
        }
        .animation(
            LeanMotion.dragSource.unlessReducingMotion(reduceMotion),
            value: [
                state.layout.topSpace(for: id), state.layout.bottomSpace(for: id), lifted ? state.layout.height : 0,
            ])
    }
}

struct BrowserSidebarReorderGap: View {
    let height: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.primary.opacity(0.035))
            .padding(.horizontal, 4).padding(.vertical, 4)
            .frame(height: height).clipped()
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct BrowserPinnedTabSlotLayout: Layout {
    let projection: BrowserPinnedTabReorderLayout

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? SidebarGeometry.width
        return CGSize(width: width, height: projection.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var resting = projection
        resting.liftedIDs = []
        resting.insertionIndex = nil
        for (index, subview) in subviews.enumerated() {
            let id = index < projection.ids.count ? projection.ids[index] : nil
            let frame =
                projection.frame(for: id, in: bounds) ?? resting.frame(for: id, in: bounds)
                ?? CGRect(origin: bounds.origin, size: .zero)
            subview.place(at: frame.origin, anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
}
