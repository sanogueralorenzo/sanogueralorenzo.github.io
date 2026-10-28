import SwiftUI

struct BrowserSpaceSwitcher: View {
    let store: BrowserStore
    let edit: (BrowserSpace?) -> Void
    @State private var firstVisible = 0
    @Namespace private var selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var spaces: [BrowserSpace] { store.session.spaces }
    private var width: CGFloat { min(max(CGFloat(spaces.count) * 28 + 4, 56), 100) }
    private var overflows: Bool { CGFloat(spaces.count) * 28 + 4 > width }

    var body: some View {
        ScrollViewReader { reader in
            HStack(spacing: 0) {
                if overflows { scrollButton(forward: false, reader: reader) }
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(spaces) { space in
                            Button {
                                guard !store.owner.sidebarDrag.suppressesActivation else { return }
                                store.selectSpace(space.id)
                            } label: {
                                Circle().fill(Color.space(space.color)).frame(width: 12, height: 12)
                                    .frame(width: 28, height: 20)
                                    .background {
                                        if store.activeSpace.id == space.id {
                                            Capsule().fill(.primary.opacity(0.12))
                                                .matchedGeometryEffect(id: "selection", in: selection)
                                        }
                                    }
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
                                LeanMotion.dragSource.unlessReducingMotion(reduceMotion),
                                value: store.sidebarReorder.spaceLayout?.targetID
                            )
                            .accessibilityHint("Select this Space, or drag to reorder")
                            .id(space.id)
                        }
                    }
                    .animation(
                        store.sidebarSpaceStep != nil && store.owner.sidebarDrag.payload == nil
                            ? LeanMotion.spaceSwitch.unlessReducingMotion(reduceMotion) : nil,
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
                .scrollIndicators(.never).scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global)
                } action: {
                    store.sidebarReorder.updateSpaceViewport($0)
                }
                .onDisappear { store.sidebarReorder.updateSpaceViewport(.zero) }
                .onScrollGeometryChange(for: Int.self) { geometry in
                    Int(max(0, geometry.contentOffset.x) / 28)
                } action: { _, index in
                    firstVisible = index
                }
                if overflows { scrollButton(forward: true, reader: reader) }
            }
            .frame(width: width, height: 24)
            .modifier(BrowserDropArea(store: store, spaceID: store.activeSpace.id, isSpaceRail: true))
            .background(LeanColor.hover, in: Capsule())
            .overlay { Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5).allowsHitTesting(false) }
            .contextMenu { Button("New Space") { edit(nil) } }
            .onChange(of: store.activeSpace.id) { _, id in
                withAnimation(
                    store.sidebarSpaceStep != nil && store.owner.sidebarDrag.payload == nil
                        ? LeanMotion.spaceSwitch.unlessReducingMotion(reduceMotion) : nil
                ) {
                    reader.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func scrollButton(forward: Bool, reader: ScrollViewProxy) -> some View {
        Button {
            firstVisible = min(max(firstVisible + (forward ? 1 : -1), 0), max(0, spaces.count - 2))
            withAnimation(LeanMotion.scrollAlignment.unlessReducingMotion(reduceMotion)) {
                reader.scrollTo(spaces[firstVisible].id, anchor: .leading)
            }
        } label: {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(.system(size: 9, weight: .semibold)).frame(width: 14, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(forward ? "Show Next Spaces" : "Show Previous Spaces")
        .disabled(forward ? firstVisible >= spaces.count - 2 : firstVisible == 0)
    }
}
