import SwiftUI

struct BrowserTabRow: View {
    @Environment(\.sidebarSpaceID) private var presentedSpaceID
    private var space: BrowserSpace { store.sidebarSpace(presentedSpaceID) }
    let tab: BrowserTab
    let store: BrowserStore
    var pinned = false
    var depth = 0
    @State private var hovering = false
    private var selected: Bool { store.sidebarSelectedTabID(in: space) == tab.id }
    private var away: Bool { tab.savedURL != nil && !BrowserURLs.same(tab.url, tab.savedURL) }
    private var title: String { tab.customTitle ?? tab.title }
    private var removesFromSaved: Bool { tab.placement == .saved && !store.isLoaded(tab) }

    var body: some View {
        HStack(spacing: 0) {
            if store.editingTabID == tab.id {
                HStack(spacing: 9) {
                    TabIcon(tab: tab)
                    InlineNameField(
                        title: title, commit: { store.renameTab(tab.id, to: $0) }, cancel: { store.editingTabID = nil })
                }.padding(.horizontal, 9)
            } else {
                Button {
                    store.clickTab(tab.id)
                } label: {
                    Group {
                        if pinned {
                            TabIcon(tab: tab)
                        } else {
                            HStack(spacing: 9) {
                                if space.folders.contains(where: { $0.id == tab.folderID && $0.kind == .github }) {
                                    Circle().fill(.green).frame(width: 6, height: 6).frame(width: 20, height: 20)
                                } else {
                                    TabIcon(tab: tab)
                                }
                                Text(title).fontWeight(selected ? .medium : .regular).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .frame(
                        maxWidth: .infinity, minHeight: SidebarGeometry.rowHeight,
                        alignment: pinned ? .center : .leading
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .help(pinned ? title : "")
                .padding(.leading, pinned ? 0 : 9)
                if showsAction {
                    let remove = removesFromSaved
                    Button {
                        guard !store.owner.sidebarDrag.suppressesActivation else { return }
                        if remove {
                            store.requestDeleteTabs([tab.id])
                        } else {
                            store.requestCloseTab(tab.id)
                        }
                    } label: {
                        Image(
                            systemName: remove || tab.placement == .current
                                ? "xmark" : away ? "arrow.uturn.backward" : "minus"
                        )
                        .font(.system(size: 12, weight: .regular))
                    }
                    .buttonStyle(BrowserChromeButtonStyle(controlSize: CGSize(width: 28, height: 28), cornerRadius: 14))
                    .padding(.trailing, pinned ? 0 : 6)
                    .accessibilityLabel(remove ? "Remove from Saved" : closeLabel)
                    .help(remove ? "Remove from Saved" : tab.placement == .current ? "Close Tab (⌘W)" : closeLabel)
                } else if !pinned {
                    Color.clear.frame(width: tab.placement == .current ? 34 : 6, height: 1)
                }
            }
        }
        .frame(height: SidebarGeometry.rowHeight)
        .foregroundStyle(store.isLoaded(tab) ? Color.primary : Color.secondary)
        .browserInteractiveSurface(
            isSelected: selected || (store.selectedTabs.contains(tab.id) && !store.selectionCovers(tab.folderID)),
            isHovering: hovering,
            cornerRadius: max(0, 10 - CGFloat(depth) * 2), cornerStyle: .circular,
            selectionEmphasis: store.sidebarKeyboardSelection && store.selectedTabs.contains(tab.id),
            showsRestingSurface: pinned, selectedBorderColor: pinned ? .clear : BrowserColor.selectedBorder,
            selectedBorderWidth: pinned ? 0.5 : 1,
            customSelectedFill: Color.space(space.color).opacity(0.32),
            customRestingFill: pinned ? Color.primary.opacity(0.055) : nil
        )
        .overlay { BrowserSidebarNestHighlight(state: store.sidebarReorder, target: .currentTab(tab.id)) }
        .overlay { BrowserTabAuxiliaryClick(store: store, tabID: tab.id).accessibilityHidden(true) }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain).accessibilityLabel(title)
        .contextMenu {
            if store.sidebarKeyboardSelection && store.selectedTabs.contains(tab.id) {
                BrowserSidebarBatchMenu(store: store)
            } else {
                contextMenu
            }
        }
        .modifier(
            BrowserSidebarDragSource(
                store: store, payload: { store.dragPayload(tab: tab.id) }, title: title, url: tab.url,
                isEnabled: store.editingTabID != tab.id)
        )
        .modifier(BrowserDropArea(store: store, before: tab.id))
        .modifier(
            BrowserSidebarReorderItem(
                store: store, id: tab.id, placement: tab.placement, folderID: tab.folderID,
                parentItemID: space.splits.first { $0.tabIDs.contains(tab.id) }?.id)
        )
        .transition(.opacity)
    }

    private var showsAction: Bool {
        if pinned { return selected && away }
        if tab.placement == .current { return selected || hovering }
        return true
    }

    private var closeLabel: String {
        if tab.placement == .current { return "Close Tab" }
        return away ? "Return to Saved URL" : "Sleep Tab"
    }

    @ViewBuilder
    private var contextMenu: some View {
        if let url = tab.url {
            Button("Copy Link URL", systemImage: "link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
            Divider()
        }
        Button("Rename Tab…") { store.editingTabID = tab.id }
        if !tab.isSettings {
            if tab.placement != .pinned {
                Button("Pin Tab") { store.placeTabs(store.actionTabs(tab.id), as: .pinned) }
            }
            if tab.placement != .saved {
                Button("Move to Saved") { store.placeTabs(store.actionTabs(tab.id), as: .saved) }
            }
            if tab.placement != .current {
                Button(tab.placement == .pinned ? "Unpin Tab" : "Move to Tabs") {
                    store.placeTabs(store.actionTabs(tab.id), as: .current)
                }
            }
            if let selected = store.selectedTab?.id, space.id == store.activeSpace.id,
                store.canSplit(beside: selected, with: tab)
            {
                Button("Split with Active Tab", systemImage: "rectangle.split.2x1") {
                    store.split(selected, with: tab.id)
                }
            }
            let folders = space.folders.filter { $0.kind == .regular }
            if tab.placement == .current || !folders.isEmpty {
                Menu("Move to Folder", systemImage: "folder") {
                    if tab.placement == .current {
                        Button("New Folder") {
                            store.createSidebarFolder(
                                containing: BrowserDragPayload(
                                    kind: .tabs,
                                    spaceID: space.id, ids: store.actionTabs(tab.id),
                                    activeTabID: store.selectedTab?.id),
                                placement: .current)
                        }
                    }
                    ForEach(folders) { folder in
                        Button(folder.title) {
                            store.placeTabs(store.actionTabs(tab.id), as: folder.placement ?? .saved, folderID: folder.id)
                        }
                        .disabled(folder.id == tab.folderID)
                    }
                }
            }
            if tab.folderID != nil {
                Button("Remove from Folder") { store.placeTabs(store.actionTabs(tab.id), as: tab.placement) }
            }
        }
        if let split = space.splits.first(where: { $0.tabIDs.contains(tab.id) }),
            let index = split.tabIDs.firstIndex(of: tab.id)
        {
            let vertical = split.direction == .vertical
            if index > 0 {
                Button(vertical ? "Move Up" : "Move Left", systemImage: vertical ? "arrow.up" : "arrow.left") {
                    store.selectTab(tab.id)
                    store.moveSplitCard(-1)
                }
            }
            if index < split.tabIDs.count - 1 {
                Button(vertical ? "Move Down" : "Move Right", systemImage: vertical ? "arrow.down" : "arrow.right") {
                    store.selectTab(tab.id)
                    store.moveSplitCard(1)
                }
            }
            Button("Remove from Split", systemImage: "rectangle.badge.minus") {
                store.detachFromSplits(tab.id)
                store.changed()
            }
        }
        let destinations = store.session.spaces.filter { $0.id != space.id && space.canMoveItems(to: $0) }
        if !destinations.isEmpty {
            Menu("Move to Space") {
                ForEach(destinations) { destination in
                    Button(destination.name) { store.moveTabs(store.actionTabs(tab.id), to: destination.id) }
                }
            }
        }
        Divider()
        Button("Duplicate Tab") { store.duplicateTab(tab.id) }
        Button(tab.placement == .current ? "Close Tab" : "Delete Tab", role: .destructive) {
            store.requestDeleteTabs([tab.id])
        }
    }
}

struct TabIcon: View {
    let tab: BrowserTab
    var body: some View {
        Group {
            if tab.isSettings {
                Image(systemName: "gearshape")
            } else if tab.url?.host == "github.com" {
                Image("AboutGitHub").resizable().renderingMode(.template).scaledToFit()
            } else if let data = tab.favicon, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "globe")
            }
        }
        .frame(width: 20, height: 20)
    }
}

struct InlineNameField: View {
    let title: String
    let commit: (String) -> Void
    let cancel: () -> Void
    @State private var text = ""
    @State private var completed = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $text).textFieldStyle(.plain)
            .focused($focused).onSubmit(finish)
            .onAppear {
                text = title
                DispatchQueue.main.async { focused = true }
            }
            .onExitCommand {
                guard !completed else { return }
                completed = true
                cancel()
            }
            .onChange(of: focused) { if !focused { finish() } }
            .onDisappear(perform: finish)
    }

    private func finish() {
        guard !completed else { return }
        completed = true
        commit(text)
    }
}
