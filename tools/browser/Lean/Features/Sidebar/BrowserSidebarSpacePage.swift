import SwiftUI

struct BrowserSidebarSpacePage: View {
    let store: BrowserStore
    let space: BrowserSpace
    private var spaceID: UUID { space.id }
    private let restoreOffset: CGFloat
    @State private var listHovered = false
    @State private var listHeight: CGFloat = 0
    @State private var position: ScrollPosition
    @State private var restoring = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: BrowserStore, space: BrowserSpace) {
        self.store = store
        self.space = space
        restoreOffset = store.sidebarScrollOffsets[space.id] ?? 0
        _position = State(initialValue: ScrollPosition(y: restoreOffset))
    }

    var body: some View {
        VStack(spacing: 0) {
            pinnedTabs
            GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: 0) {
                        tabRows.onGeometryChange(for: CGFloat.self) {
                            $0.size.height
                        } action: {
                            listHeight = $0
                        }
                        BrowserSidebarBackground(store: store)
                            .frame(height: max(0, viewport.size.height - listHeight))
                    }
                }
                .scrollIndicators(.never)
                .scrollPosition($position)
                .onAppear {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { position.scrollTo(y: restoreOffset) }
                }
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global)
                } action: {
                    guard store.activeSpace.id == spaceID else { return }
                    store.sidebarReorder.updateScrollViewport(
                        $0, in: store)
                }
                .onDisappear {
                    if store.activeSpace.id == spaceID { store.sidebarReorder.updateScrollViewport(nil, in: store) }
                }
                .onScrollGeometryChange(for: CGPoint.self) {
                    CGPoint(x: max(0, $0.contentSize.height - $0.containerSize.height), y: $0.contentOffset.y)
                } action: { old, new in
                    guard store.activeSpace.id == spaceID else { return }
                    // Initial layout can report zero before the saved position is applied.
                    guard !restoring || abs(new.y - min(restoreOffset, new.x)) < 1 else { return }
                    restoring = false
                    store.sidebarScrollOffsets[spaceID] = max(0, new.y)
                    store.sidebarReorder.scroll(by: old.y - new.y, in: store)
                }
                .onHover { listHovered = $0 }
            }
        }
        .animation(LeanMotion.collection.unlessReducingMotion(reduceMotion), value: space.orderedSidebarIDs)
    }

    private var tabRows: some View {
        VStack(spacing: 2) {
            VStack(spacing: 2) { BrowserSidebarList(store: store, placement: .saved) }
                .modifier(BrowserDropArea(store: store, placement: .saved))
            currentDivider
                .frame(
                    height: store.sidebarReorder.showsCurrentDivider(in: store, space: space)
                        ? SidebarGeometry.currentDividerHeight : 0
                )
                .clipped().allowsHitTesting(store.sidebarReorder.showsCurrentDivider(in: store, space: space))
                .accessibilityHidden(!store.sidebarReorder.showsCurrentDivider(in: store, space: space))
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global)
                } action: {
                    store.sidebarReorder.registerDivider($0)
                }
            VStack(spacing: 2) { BrowserSidebarList(store: store, placement: .current) }
                .modifier(BrowserDropArea(store: store, placement: .current))
            newTab
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var pinnedTabs: some View {
        let projection = store.sidebarReorder.pinnedLayout(in: space, width: store.sidebarWidth - 32)
        return
            BrowserPinnedTabSlotLayout(
                projection: projection
            ) {
                ForEach(pins) { BrowserSidebarItem(tab: $0, store: store, pinned: true) }
                RoundedRectangle(cornerRadius: 20).fill(.primary.opacity(0.035))
                    .opacity(store.sidebarReorder.target?.isPinned == true ? 1 : 0)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .padding(.top, projection.height > 0 ? SidebarGeometry.pinnedTopInset : 0)
            .padding(.bottom, projection.height > 0 ? SidebarGeometry.pinnedBottomInset : 0)
            .modifier(BrowserDropArea(store: store, placement: .pinned))
            .padding(.horizontal, 16)
            .animation(LeanMotion.collection.unlessReducingMotion(reduceMotion), value: pins.map(\.id))
            .animation(LeanMotion.dragSource.unlessReducingMotion(reduceMotion), value: store.sidebarReorder.target)
            .animation(
                LeanMotion.dragSource.unlessReducingMotion(reduceMotion), value: store.owner.sidebarDrag.lift?.rootIDs)
    }

    private var currentDivider: some View {
        HStack(spacing: 8) {
            Rectangle().fill(LeanBrandTheme.line).frame(height: 0.5)
            if listHovered {
                Button {
                    store.clearCurrentTabs()
                } label: {
                    HStack(spacing: 4) {
                        Text("Clear")
                        BrowserShortcutHint(text: "⇧⌘K")
                        Image(systemName: "archivebox")
                    }.padding(.horizontal, 8).frame(height: 28)
                }
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                .buttonStyle(LeanChromeButtonStyle(controlSize: nil, cornerRadius: 14))
                .accessibilityLabel("Archive Current Tabs")
            }
        }.frame(height: SidebarGeometry.currentDividerHeight)
    }

    private var newTab: some View {
        Button {
            store.presentAddress(newTab: true)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 17)).frame(width: 28)
                Text("New Tab")
                Spacer(minLength: 0)
                BrowserShortcutHint(text: "⌘T")
            }
            .padding(.horizontal, 9)
            .frame(height: SidebarGeometry.rowHeight)
            .contentShape(Rectangle())
        }
        .foregroundStyle(.secondary)
        .buttonStyle(LeanChromeButtonStyle(controlSize: nil, cornerRadius: 20))
        .accessibilityIdentifier("new-tab")
    }

    private var pins: [BrowserTab] { space.pinnedTabs }
}
