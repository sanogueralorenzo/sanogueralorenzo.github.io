import AppKit
import SwiftUI

struct BrowserSpaceSwitcher: View {
    let store: BrowserStore
    let edit: (BrowserSpace?) -> Void
    @State private var position = ScrollPosition(x: 0)
    @State private var scroll = CGPoint.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let spacing: CGFloat = 2
    private let inset: CGFloat = 2
    private var spaces: [BrowserSpace] { store.session.spaces }

    var body: some View {
        let tabs = spaceTabs
        let starts = tabs.map(\.start)
        let contentWidth = (tabs.last.map { $0.start + $0.width } ?? 0) + 2 * inset
        let width = min(contentWidth, store.sidebarWidth - 2 * SidebarGeometry.contentInset)
        let overflows = contentWidth > width
        ScrollViewReader { reader in
            HStack(spacing: 0) {
                if overflows { scrollButton(forward: false, starts: starts) }
                ScrollView(.horizontal) {
                    HStack(spacing: spacing) {
                        ForEach(tabs, id: \.space.id) { tab in
                            let space = tab.space
                            let selected = store.activeSpace.id == space.id
                            let label = space.isPrivate ? "\(space.name), Private Space" : space.name
                            Button {
                                guard !store.owner.sidebarDrag.suppressesActivation else { return }
                                store.selectSpace(space.id)
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
                if overflows { scrollButton(forward: true, starts: starts) }
            }
            .frame(width: width, height: BrowserSpaceTabLabel.height + 2 * inset)
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

    private var spaceTabs: [(space: BrowserSpace, width: CGFloat, start: CGFloat)] {
        var start: CGFloat = 0
        return spaces.map { space in
            let width = BrowserSpaceTabLabel.width(for: space.name)
            defer { start += width + spacing }
            return (space, width, start)
        }
    }

    private func scrollButton(forward: Bool, starts: [CGFloat]) -> some View {
        Button {
            let next = forward ? starts.first { $0 > scroll.x + 0.5 } : starts.last { $0 < scroll.x - 0.5 }
            withAnimation(BrowserMotion.scrollAlignment.unlessReducingMotion(reduceMotion)) {
                position.scrollTo(x: min(next ?? (forward ? scroll.y : 0), scroll.y))
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
