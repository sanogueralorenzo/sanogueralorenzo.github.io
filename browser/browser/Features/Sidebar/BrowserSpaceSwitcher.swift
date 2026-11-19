import SwiftUI

struct BrowserSpaceSwitcher: View {
    let store: BrowserStore
    let edit: (BrowserSpace?) -> Void
    @State private var position = ScrollPosition(x: 0)
    @State private var scroll = CGPoint.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let itemWidth: CGFloat = 72
    private var spaces: [BrowserSpace] { store.session.spaces }
    private var contentWidth: CGFloat { CGFloat(spaces.count) * itemWidth + 4 }
    private var width: CGFloat {
        min(contentWidth, store.sidebarWidth - SidebarGeometry.titlebarLeadingSpace
            - 2 * SidebarGeometry.titlebarHorizontalInset - 3 * SidebarGeometry.titlebarSpacing
            - BrowserLayout.minimumHitTarget)
    }
    private var overflows: Bool { contentWidth > width }

    var body: some View {
        ScrollViewReader { reader in
            HStack(spacing: 0) {
                if overflows { scrollButton(forward: false) }
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(spaces) { space in
                            Button {
                                guard !store.owner.sidebarDrag.suppressesActivation else { return }
                                store.selectSpace(space.id)
                            } label: {
                                HStack(spacing: 5) {
                                    Circle().fill(Color.space(space.color)).frame(width: 7, height: 7)
                                    Text(space.name).lineLimit(1).minimumScaleFactor(0.85)
                                }
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 5)
                                .frame(height: 22)
                                .background(
                                    .primary.opacity(store.activeSpace.id == space.id ? 0.13 : 0), in: Capsule())
                                .frame(width: itemWidth)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(space.name)
                            .accessibilityAddTraits(store.activeSpace.id == space.id ? .isSelected : [])
                            .help(space.name)
                            .contextMenu {
                                if let index = spaces.firstIndex(where: { $0.id == space.id }) {
                                    Button("Move Left", systemImage: "arrow.left") {
                                        store.moveSpace(space.id, by: -1)
                                    }.disabled(index == 0)
                                    Button("Move Right", systemImage: "arrow.right") {
                                        store.moveSpace(space.id, by: 1)
                                    }.disabled(index == spaces.count - 1)
                                    Divider()
                                }
                                Button("New Space") { edit(nil) }
                                Button("Edit Space") { edit(space) }
                                Button("Delete Space", role: .destructive) { store.deleteSpace(space.id) }
                                    .disabled(!space.isPrivate && spaces.filter { !$0.isPrivate }.count == 1)
                            }
                            .modifier(
                                BrowserSidebarDragSource(
                                    store: store, payload: { store.dragPayload(space: space.id) }, title: space.name,
                                    isEnabled: !store.sidebarSpaceTransitioning)
                            )
                            .modifier(BrowserDropArea(store: store, spaceID: space.id))
                            .opacity(
                                store.sidebarReorder.spaceLayout?.sourceID == space.id
                                    || store.owner.sidebarDrag.landingIDs.contains(space.id) ? 0 : 1
                            )
                            .offset(x: store.sidebarReorder.spaceLayout?.offset(for: space.id) ?? 0)
                            .animation(
                                BrowserMotion.dragSource.unlessReducingMotion(reduceMotion),
                                value: store.sidebarReorder.spaceLayout?.targetID
                            )
                            .accessibilityHint("Select this Space, or drag to reorder")
                            .id(space.id)
                        }
                    }
                    .animation(
                        store.sidebarSpaceStep != nil && store.owner.sidebarDrag.payload == nil
                            ? BrowserMotion.spaceSwitch.unlessReducingMotion(reduceMotion) : nil,
                        value: store.activeSpace.id
                    )
                    .padding(2).frame(minWidth: overflows ? 0 : width, alignment: .center)
                    .background {
                        BrowserSpacePickerAutoscroll(
                            viewport: store.sidebarReorder.spaceViewport,
                            pointer: store.sidebarReorder.spaceLayout?.pointer
                        ) { delta in
                            store.sidebarReorder.spaceContentMoved(by: delta)
                        }
                    }
                }
                .scrollPosition($position)
                .scrollIndicators(.never).scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global)
                } action: {
                    store.sidebarReorder.updateSpaceViewport($0)
                }
                .onDisappear { store.sidebarReorder.updateSpaceViewport(.zero) }
                .onScrollGeometryChange(for: CGPoint.self) { geometry in
                    CGPoint(
                        x: max(0, geometry.contentOffset.x),
                        y: max(0, geometry.contentSize.width - geometry.containerSize.width))
                } action: { _, value in
                    scroll = value
                }
                if overflows { scrollButton(forward: true) }
            }
            .frame(width: width, height: 24)
            .modifier(BrowserDropArea(store: store, spaceID: store.activeSpace.id, isSpaceRail: true))
            .contextMenu { Button("New Space") { edit(nil) } }
            .onAppear { reader.scrollTo(store.activeSpace.id, anchor: .center) }
            .onChange(of: store.activeSpace.id) { _, id in
                withAnimation(
                    store.sidebarSpaceStep != nil && store.owner.sidebarDrag.payload == nil
                        ? BrowserMotion.spaceSwitch.unlessReducingMotion(reduceMotion) : nil
                ) {
                    reader.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func scrollButton(forward: Bool) -> some View {
        Button {
            withAnimation(BrowserMotion.scrollAlignment.unlessReducingMotion(reduceMotion)) {
                position.scrollTo(x: min(max(0, scroll.x + (forward ? itemWidth : -itemWidth)), scroll.y))
            }
        } label: {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(.system(size: 9, weight: .semibold)).frame(width: 14, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(forward ? "Show Next Spaces" : "Show Previous Spaces")
        .disabled(forward ? scroll.x >= scroll.y - 0.5 : scroll.x <= 0.5)
    }
}
