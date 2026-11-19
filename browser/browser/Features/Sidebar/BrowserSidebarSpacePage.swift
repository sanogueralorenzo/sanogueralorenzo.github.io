import SwiftUI

struct BrowserSidebarSpacePage: View {
    let store: BrowserStore
    let space: BrowserSpace
    private var spaceID: UUID { space.id }
    private let restoreOffset: CGFloat
    @State private var listHeight: CGFloat = 0
    @State private var position: ScrollPosition
    @State private var restoring = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var savedExpanded: Bool { store.expandedSavedSpaces.contains(spaceID) }

    init(store: BrowserStore, space: BrowserSpace) {
        self.store = store
        self.space = space
        restoreOffset = store.sidebarScrollOffsets[space.id] ?? 0
        _position = State(initialValue: ScrollPosition(y: restoreOffset))
    }

    var body: some View {
        VStack(spacing: SidebarGeometry.panelSpacing) {
            VStack(spacing: 0) {
                sectionTitle("Pinned").padding(.horizontal, SidebarGeometry.panelPadding)
                pinnedTabs
            }
            .padding(.top, SidebarGeometry.panelPadding)
            .browserSidebarPanel()
            GeometryReader { viewport in
                let unusedHeight = max(0, viewport.size.height - listHeight)
                let canResizeBackdrop = !store.sidebarSpaceTransitioning || unusedHeight < store.sidebarUnusedHeight
                let backdropInset = spaceID == store.activeSpace.id && listHeight > 0 && canResizeBackdrop
                    ? unusedHeight : nil
                ScrollView {
                    VStack(spacing: 0) {
                        scrollingSections.onGeometryChange(for: CGFloat.self) {
                            $0.size.height
                        } action: {
                            listHeight = $0
                        }
                        BrowserSidebarBackground(store: store)
                            .frame(height: unusedHeight)
                    }
                }
                .onChange(of: backdropInset, initial: true) { _, height in
                    if let height { store.sidebarUnusedHeight = height }
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
            }
        }
        .animation(BrowserMotion.collection.unlessReducingMotion(reduceMotion), value: space.orderedSidebarIDs)
        .onChange(of: space.hasSavedItems, initial: true) { _, hasItems in
            if !hasItems { store.expandedSavedSpaces.remove(spaceID) }
        }
    }

    private var scrollingSections: some View {
        VStack(spacing: SidebarGeometry.panelSpacing) {
            let liveFolders = space.liveFolders
            if !liveFolders.isEmpty {
                VStack(spacing: 4) {
                    sectionTitle("Live")
                    ForEach(liveFolders) { folder in
                        BrowserFolderRow(folder: folder, store: store, depth: 0)
                    }
                }
                .padding(SidebarGeometry.panelPadding)
                .browserSidebarPanel()
            }
            if space.hasSavedItems {
                savedSection
            }
            VStack(spacing: 4) {
                tabsHeader
                BrowserSidebarList(store: store, placement: .current)
                    .frame(maxWidth: .infinity, minHeight: 8)
                    .modifier(BrowserDropArea(store: store, placement: .current))
                newTab
            }
            .padding(SidebarGeometry.panelPadding)
            .browserSidebarPanel()
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var savedSection: some View {
        VStack(spacing: 4) {
            Button {
                guard !store.owner.sidebarDrag.suppressesActivation else { return }
                store.clearSidebarSelection()
                withAnimation(BrowserMotion.disclosure.unlessReducingMotion(reduceMotion)) {
                    if savedExpanded {
                        store.expandedSavedSpaces.remove(spaceID)
                    } else {
                        store.expandedSavedSpaces.insert(spaceID)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bookmark").foregroundStyle(.secondary)
                    Text("Saved").font(.headline)
                    Spacer(minLength: 0)
                    Image(systemName: savedExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, SidebarGeometry.panelPadding)
                .frame(height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(BrowserChromeButtonStyle(controlSize: nil, cornerRadius: SidebarGeometry.panelRadius))
            .accessibilityLabel("Saved")
            .accessibilityValue(savedExpanded ? "Expanded" : "Collapsed")
            if savedExpanded {
                BrowserSidebarList(store: store, placement: .saved)
                    .padding([.horizontal, .bottom], SidebarGeometry.panelPadding)
            }
        }
        .modifier(BrowserDropArea(store: store, placement: .saved))
        .browserSidebarPanel()
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private var pinnedTabs: some View {
        let projection = store.sidebarReorder.pinnedLayout(
            in: space, width: store.sidebarWidth - 2 * (SidebarGeometry.panelSpacing + SidebarGeometry.panelPadding))
        return
            BrowserPinnedTabSlotLayout(
                projection: projection
            ) {
                ForEach(pins) { BrowserSidebarItem(tab: $0, store: store, pinned: true) }
                RoundedRectangle(cornerRadius: 20).fill(.primary.opacity(0.035))
                    .opacity(store.sidebarReorder.target?.isPinned == true ? 1 : 0)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .frame(minHeight: 8)
            .padding(.top, SidebarGeometry.pinnedTopInset)
            .padding(.bottom, SidebarGeometry.pinnedBottomInset)
            .modifier(BrowserDropArea(store: store, placement: .pinned))
            .padding(.horizontal, SidebarGeometry.panelPadding)
            .animation(BrowserMotion.collection.unlessReducingMotion(reduceMotion), value: pins.map(\.id))
            .animation(BrowserMotion.dragSource.unlessReducingMotion(reduceMotion), value: store.sidebarReorder.target)
            .animation(
                BrowserMotion.dragSource.unlessReducingMotion(reduceMotion), value: store.owner.sidebarDrag.lift?.rootIDs)
    }

    private var tabsHeader: some View {
        HStack(spacing: 8) {
            sectionTitle("Tabs")
            if !space.hasSavedItems, let drag = store.owner.sidebarDrag.payload, drag.kind != .space {
                Text("Drop to save")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: BrowserLayout.minimumHitTarget)
                    .background(BrowserBrandTheme.line.opacity(0.35), in: Capsule())
                    .modifier(BrowserDropArea(store: store, placement: .saved, showsInsertionGap: false))
            } else if space.tabs.lazy.filter({ $0.placement == .current && !$0.isSettings }).prefix(2).count == 2 {
                Button {
                    store.clearCurrentTabs()
                } label: {
                    HStack(spacing: 4) {
                        Text("Clear")
                        BrowserShortcutHint(text: "⇧⌘K")
                        Image(systemName: "archivebox")
                    }.padding(.horizontal, 6).frame(height: BrowserLayout.minimumHitTarget)
                }
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                .buttonStyle(BrowserChromeButtonStyle(controlSize: nil, cornerRadius: 14))
                .accessibilityLabel("Archive Current Tabs")
            }
        }.frame(height: BrowserLayout.minimumHitTarget)
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
        .buttonStyle(BrowserChromeButtonStyle(controlSize: nil, cornerRadius: 20))
        .accessibilityIdentifier("new-tab")
    }

    private var pins: [BrowserTab] { space.pinnedTabs }
}
