import SwiftUI

struct BrowserTabRow: View {
    let tab: BrowserTab
    let store: BrowserStore
    var pinned = false
    @State private var hovering = false
    private var selected: Bool { store.selectedTab?.id == tab.id }
    private var away: Bool { tab.savedURL != nil && !BrowserURLs.same(tab.url, tab.savedURL) }
    private var title: String { tab.customTitle ?? tab.title }

    var body: some View {
        HStack(spacing: 2) {
            if store.editingTabID == tab.id {
                InlineNameField(title: title) { store.renameTab(tab.id, to: $0) }
                    .padding(.horizontal, 8)
            } else {
                Button {
                    store.clickTab(tab.id)
                } label: {
                    HStack(spacing: 9) {
                        if store.activeSpace.folders.contains(where: { $0.id == tab.folderID && $0.kind == .github }) {
                            Circle().fill(.green).frame(width: 6, height: 6).frame(width: 20, height: 20)
                        } else {
                            TabIcon(tab: tab).frame(width: 20, height: 20)
                        }
                        if !pinned { Text(title).lineLimit(1) }
                        if !pinned || selected { Spacer(minLength: 0) }
                    }
                    .frame(
                        maxWidth: .infinity, minHeight: SidebarGeometry.rowHeight,
                        alignment: pinned && !selected ? .center : .leading
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 9)
                if selected { BrowserShortcutHint(text: "⌘W") }
                if showsAction {
                    Button {
                        if tab.placement == .current {
                            store.requestDeleteTabs([tab.id])
                        } else if let url = tab.savedURL, away {
                            store.navigate(url, in: tab.id)
                        } else {
                            store.selectTab(tab.id)
                            store.closeSelectedTab()
                        }
                    } label: {
                        Image(systemName: tab.placement == .current ? "xmark" : away ? "arrow.uturn.backward" : "minus")
                            .font(.system(size: 12, weight: .regular))
                    }
                    .buttonStyle(CrestChromeButtonStyle(controlSize: CGSize(width: 28, height: 28), cornerRadius: 14))
                    .padding(.trailing, 6)
                    .accessibilityLabel(
                        tab.placement == .current ? "Close Tab" : away ? "Return to Saved URL" : "Sleep Tab")
                } else {
                    Color.clear.frame(width: pinned ? 8 : 5, height: 1)
                }
            }
        }
        .frame(height: SidebarGeometry.rowHeight)
        .foregroundStyle(store.isLoaded(tab) ? Color.primary : Color.secondary)
        .crestInteractiveSurface(
            isSelected: selected || store.selectedTabs.contains(tab.id), isHovering: hovering, cornerRadius: 20,
            showsRestingSurface: pinned
        )
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain).accessibilityLabel(title)
        .contextMenu { contextMenu }
        .onDrag { store.dragProvider(tab: tab.id) }
        .modifier(BrowserDropArea(store: store, before: tab.id))
    }

    private var showsAction: Bool {
        if pinned && !selected { return false }
        if tab.placement == .current { return selected || hovering }
        return away || store.isLoaded(tab)
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Rename") { store.editingTabID = tab.id }
        if !tab.isSettings {
            if tab.placement != .pinned {
                Button("Pin Tab") { store.placeTabs(store.actionTabs(tab.id), as: .pinned) }
            }
            if tab.placement != .saved || tab.folderID != nil {
                Button("Move to Saved Tabs") { store.placeTabs(store.actionTabs(tab.id), as: .saved) }
            }
            if tab.placement != .current {
                Button("Move to Current Tabs") { store.placeTabs(store.actionTabs(tab.id), as: .current) }
            }
            Menu("Split With") {
                Button("New Tab") { store.beginSplit(with: tab.id) }
                ForEach(store.activeSpace.tabs.filter { $0.id != tab.id && !$0.isSettings }) { other in
                    Button(other.customTitle ?? other.title) { store.split(tab.id, with: other.id) }
                }
            }
            Menu("Save in Folder") {
                ForEach(store.activeSpace.folders.filter { $0.kind == .regular }) { folder in
                    Button(folder.title) { store.placeTabs(store.actionTabs(tab.id), as: .saved, folderID: folder.id) }
                }
            }
        }
        Menu("Move to Space") {
            ForEach(store.session.spaces.filter { $0.id != store.activeSpace.id }) { space in
                Button(space.name) { store.moveTabs(store.actionTabs(tab.id), to: space.id) }
            }
        }
        Divider()
        Button("Duplicate") { store.duplicateTabs(store.actionTabs(tab.id)) }
        Button("Delete Tabs", role: .destructive) { store.requestDeleteTabs(store.actionTabs(tab.id)) }
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
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $text).textFieldStyle(.plain)
            .focused($focused).onSubmit { commit(text) }
            .onAppear {
                text = title
                focused = true
            }
            .onExitCommand {
                text = title
                commit(title)
            }
            .onChange(of: focused) { if !focused && text != title { commit(text) } }
    }
}
