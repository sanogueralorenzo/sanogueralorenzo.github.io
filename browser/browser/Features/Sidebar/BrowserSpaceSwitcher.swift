import AppKit
import SwiftUI

struct BrowserSpaceSwitcher: View {
    let store: BrowserStore
    let edit: (BrowserSpace?) -> Void
    @State private var overflow: Edge.Set = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let spacing: CGFloat = 2
    private let inset: CGFloat = 2
    private var spaces: [BrowserSpace] { store.session.spaces }

    var body: some View {
        let tabs = spaces.map { (space: $0, width: BrowserSpaceTabLabel.width(for: $0.name)) }
        let contentWidth = tabs.reduce(2 * inset) { $0 + $1.width } + CGFloat(max(0, tabs.count - 1)) * spacing
        let width = min(contentWidth, store.sidebarWidth - 2 * SidebarGeometry.contentInset)
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                HStack(spacing: spacing) {
                    ForEach(tabs, id: \.space.id) { tab in
                        let space = tab.space
                        let selected = store.activeSpace.id == space.id
                        let label = space.isPrivate ? "\(space.name), Private Space" : space.name
                        Button {
                            guard !store.owner.sidebarDrag.suppressesActivation else { return }
                            if selected {
                                withAnimation(BrowserMotion.scrollAlignment.unlessReducingMotion(reduceMotion)) {
                                    reader.scrollTo(space.id, anchor: .center)
                                }
                            } else {
                                store.selectSpace(space.id)
                            }
                        } label: {
                            BrowserSpaceTabLabel(name: space.name, width: tab.width, selected: selected)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(label)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .help(label)
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
                .padding(inset)
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
            .onScrollGeometryChange(for: Edge.Set.self) { geometry in
                var edges: Edge.Set = []
                if geometry.visibleRect.minX > 0.5 { edges.insert(.leading) }
                if geometry.visibleRect.maxX < geometry.contentSize.width - 0.5 { edges.insert(.trailing) }
                return edges
            } action: { _, edges in
                overflow = edges
            }
            .frame(width: width, height: BrowserSpaceTabLabel.height + 2 * inset)
            .overlay {
                HStack(spacing: 0) {
                    if overflow.contains(.leading) { edgeFade(from: .leading, to: .trailing) }
                    Spacer(minLength: 0)
                    if overflow.contains(.trailing) { edgeFade(from: .trailing, to: .leading) }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .modifier(BrowserDropArea(store: store, spaceID: store.activeSpace.id, isSpaceRail: true))
            .contextMenu { Button("New Space") { edit(nil) } }
            .onAppear { reader.scrollTo(store.activeSpace.id, anchor: .center) }
            .onChange(of: store.activeSpace.id) { _, id in
                let motion = store.sidebarSpaceStep == nil ? BrowserMotion.scrollAlignment : BrowserMotion.spaceSwitch
                withAnimation(store.owner.sidebarDrag.payload == nil ? motion.unlessReducingMotion(reduceMotion) : nil) {
                    reader.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func edgeFade(from start: UnitPoint, to end: UnitPoint) -> some View {
        LinearGradient(colors: [BrowserBrandTheme.sidebarBackdrop, .clear], startPoint: start, endPoint: end)
            .frame(width: 18)
    }
}

struct BrowserSpaceTabLabel: View {
    static let height = BrowserLayout.minimumHitTarget
    static let cornerRadius: CGFloat = 8
    private static let labelFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private static let horizontalInset: CGFloat = 10

    let name: String
    let width: CGFloat
    let selected: Bool
    @State private var hovering = false

    static func width(for name: String) -> CGFloat {
        let textWidth = (name as NSString).size(withAttributes: [.font: labelFont]).width
        return min(144, max(44, ceil(textWidth) + 2 * horizontalInset))
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius)
        Text(name)
            .font(Font(Self.labelFont))
            .lineLimit(1)
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, Self.horizontalInset)
            .frame(width: width, height: Self.height)
            .background(selected ? Color.primary.opacity(0.10) : hovering ? BrowserColor.hover : .clear, in: shape)
            .overlay { if selected { shape.strokeBorder(BrowserColor.selectedBorder, lineWidth: 0.5) } }
            .contentShape(shape)
            .onHover { hovering = $0 }
    }
}
