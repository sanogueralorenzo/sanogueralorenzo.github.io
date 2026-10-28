import SwiftUI

struct BrowserTabRow: View {
    let tab: BrowserTab
    let store: BrowserStore
    var pinned = false
    var depth = 0
    @State private var hovering = false
    private var selected: Bool { store.selectedTab?.id == tab.id }
    private var away: Bool { tab.savedURL != nil && !BrowserURLs.same(tab.url, tab.savedURL) }
    private var title: String { tab.customTitle ?? tab.title }

    var body: some View {
        HStack(spacing: 0) {
            if store.editingTabID == tab.id {
                HStack(spacing: 9) {
                    TabIcon(tab: tab).frame(width: 28, height: 20)
                    InlineNameField(
                        title: title, commit: { store.renameTab(tab.id, to: $0) }, cancel: { store.editingTabID = nil })
                }.padding(.horizontal, 9)
            } else {
                Button {
                    store.clickTab(tab.id)
                } label: {
                    HStack(spacing: 9) {
                        if store.activeSpace.folders.contains(where: { $0.id == tab.folderID && $0.kind == .github }) {
                            Circle().fill(.green).frame(width: 6, height: 6).frame(width: 20, height: 20)
                        } else {
                            TabIcon(tab: tab).frame(width: 28, height: 20)
                        }
                        if !pinned { Text(title).lineLimit(1) }
                        if !pinned { Spacer(minLength: 0) }
                    }
                    .frame(
                        maxWidth: .infinity, minHeight: SidebarGeometry.rowHeight,
                        alignment: pinned ? .center : .leading
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, pinned ? 0 : 9)
                if selected { BrowserShortcutHint(text: "⌘W") }
                if showsAction {
                    Button {
                        guard !store.owner.sidebarDrag.suppressesActivation else { return }
                        if tab.placement == .current {
                            store.requestDeleteTabs([tab.id])
                        } else if let url = tab.savedURL, away {
                            store.navigate(url, in: tab.id)
                        } else {
                            store.requestCloseTab(tab.id)
                        }
                    } label: {
                        Image(systemName: tab.placement == .current ? "xmark" : away ? "arrow.uturn.backward" : "minus")
                            .font(.system(size: 12, weight: .regular))
                    }
                    .buttonStyle(LeanChromeButtonStyle(controlSize: CGSize(width: 28, height: 28), cornerRadius: 14))
                    .padding(.trailing, 6)
                    .accessibilityLabel(
                        tab.placement == .current ? "Close Tab" : away ? "Return to Saved URL" : "Sleep Tab")
                } else if !pinned {
                    Color.clear.frame(width: tab.placement == .current ? 34 : 6, height: 1)
                }
            }
        }
        .frame(height: SidebarGeometry.rowHeight)
        .foregroundStyle(store.isLoaded(tab) ? Color.primary : Color.secondary)
        .leanInteractiveSurface(
            isSelected: selected || (store.selectedTabs.contains(tab.id) && !store.selectionCovers(tab.folderID)),
            isHovering: hovering,
            cornerRadius: max(0, 20 - CGFloat(depth) * 4), cornerStyle: .circular,
            selectionEmphasis: store.sidebarKeyboardSelection && store.selectedTabs.contains(tab.id),
            showsRestingSurface: pinned, selectedBorderColor: pinned ? .clear : LeanColor.selectedBorder,
            selectedBorderWidth: pinned ? 0.5 : 1,
            customSelectedFill: pinned ? Color.primary.opacity(0.13) : nil,
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
                parentItemID: store.activeSpace.splits.first { $0.tabIDs.contains(tab.id) }?.id)
        )
        .transition(.opacity)
    }

    private var showsAction: Bool {
        if pinned { return selected && away }
        if tab.placement == .current { return selected || hovering }
        return away || store.isLoaded(tab)
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
            if tab.placement != .saved || tab.folderID != nil {
                Button("Move to Saved Tabs") { store.placeTabs(store.actionTabs(tab.id), as: .saved) }
            }
            if tab.placement != .current {
                Button(tab.placement == .pinned ? "Unpin Tab" : "Move to Current Tabs") {
                    store.placeTabs(store.actionTabs(tab.id), as: .current)
                }
            }
            Button("Split with Current Tab", systemImage: "rectangle.split.2x1") {
                if let selected = store.selectedTab?.id { store.split(selected, with: tab.id) }
            }.disabled(store.selectedTab?.id == tab.id || store.selectedTab?.isSettings != false)
            Menu("Split With") {
                Button("New Tab") { store.beginSplit(with: tab.id) }
                ForEach(store.activeSpace.tabs.filter { $0.id != tab.id && !$0.isSettings }) { other in
                    Button(other.customTitle ?? other.title) { store.split(tab.id, with: other.id) }
                }
            }
            if tab.placement == .current {
                Menu("Add to Current Tabs Folder", systemImage: "folder.badge.plus") {
                    Button("New Folder") {
                        store.createSidebarFolder(
                            containing: BrowserDragPayload(
                                kind: .tabs,
                                spaceID: store.activeSpace.id, ids: store.actionTabs(tab.id),
                                activeTabID: store.selectedTab?.id),
                            placement: .current)
                    }
                    ForEach(store.activeSpace.folders.filter { $0.placement == .current && $0.kind == .regular }) {
                        folder in
                        Button(folder.title) {
                            store.placeTabs(store.actionTabs(tab.id), as: .current, folderID: folder.id)
                        }
                    }
                }
            }
            if tab.folderID != nil {
                Button("Remove from Folder") { store.placeTabs(store.actionTabs(tab.id), as: tab.placement) }
            }
            Menu("Save in Folder") {
                Button("Saved Tabs") { store.placeTabs(store.actionTabs(tab.id), as: .saved) }
                ForEach(store.activeSpace.folders.filter { $0.kind == .regular && ($0.placement ?? .saved) == .saved })
                { folder in
                    Button(folder.title) { store.placeTabs(store.actionTabs(tab.id), as: .saved, folderID: folder.id) }
                }
            }
        }
        if let split = store.activeSpace.splits.first(where: { $0.tabIDs.contains(tab.id) }),
            let index = split.tabIDs.firstIndex(of: tab.id)
        {
            Button("Move Left", systemImage: "arrow.left") {
                store.selectTab(tab.id)
                store.moveSplitCard(-1)
            }.disabled(index == 0)
            Button("Move Right", systemImage: "arrow.right") {
                store.selectTab(tab.id)
                store.moveSplitCard(1)
            }.disabled(index == split.tabIDs.count - 1)
            Button("Remove from Split", systemImage: "rectangle.badge.minus") {
                store.detachFromSplits(tab.id)
                store.changed()
            }
        }
        Menu("Move to Space") {
            ForEach(store.session.spaces.filter { $0.id != store.activeSpace.id }) { space in
                Button(space.name) { store.moveTabs(store.actionTabs(tab.id), to: space.id) }
            }
        }
        Divider()
        Button("Duplicate Tab") { store.duplicateTab(tab.id) }
        Button(tab.placement == .current ? "Close Tab" : "Delete Tab", role: .destructive) {
            store.requestDeleteTabs(store.actionTabs(tab.id))
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
