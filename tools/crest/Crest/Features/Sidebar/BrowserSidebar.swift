import SwiftUI

struct BrowserSidebar: View {
    let store: BrowserStore
    @State private var editingSpace: BrowserSpace?
    @State private var showsSpaceEditor = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Color.clear.frame(width: 70, height: SidebarGeometry.titlebarHeight)
                Spacer(minLength: 4)
                spaceSwitcher
            }
            navigation
            if let playing = store.playingPage { nowPlaying(playing) }
            if let utility = store.utility {
                BrowserUtilityList(utility: utility, store: store)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        if store.isDragging && pins.isEmpty { dropTarget("Pinned Tabs", placement: .pinned) }
                        if !pins.isEmpty {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                                ForEach(pins) { BrowserSidebarItem(tab: $0, store: store, pinned: true) }
                            }
                            .padding(.bottom, 8)
                        }
                        ForEach(store.visibleFolders) { entry in
                            BrowserFolderRow(folder: entry.folder, store: store, depth: entry.depth)
                        }
                        ForEach(saved) { BrowserSidebarItem(tab: $0, store: store) }
                        if store.isDragging { dropTarget("Saved Tabs", placement: .saved) }
                        if !current.isEmpty,
                            !saved.isEmpty
                                || store.visibleFolders.contains(where: {
                                    $0.folder.kind == .regular
                                        || store.integration(for: store.activeSpace.id).isSignedIn
                                })
                        {
                            Divider().padding(.vertical, 8)
                        }
                        ForEach(current) { BrowserSidebarItem(tab: $0, store: store) }
                        if store.isDragging { dropTarget("Current Tabs", placement: .current) }
                        HStack(spacing: 0) {
                            Button {
                                store.presentAddress(newTab: true)
                            } label: {
                                HStack {
                                    Image(systemName: "plus").frame(width: 20)
                                    Text("New Tab")
                                    Spacer(minLength: 2)
                                    BrowserShortcutHint(text: "⌘T")
                                }
                                .frame(height: SidebarGeometry.rowHeight).padding(.horizontal, 10)
                            }
                            .buttonStyle(CrestChromeButtonStyle(controlSize: nil, cornerRadius: 20))
                            if !current.isEmpty {
                                Divider().frame(height: 20).padding(.horizontal, 6)
                                Button {
                                    store.clearCurrentTabs()
                                } label: {
                                    Image(systemName: "archivebox")
                                }
                                .accessibilityLabel("Archive Current Tabs")
                                .buttonStyle(
                                    CrestChromeButtonStyle(controlSize: CGSize(width: 36, height: 36), cornerRadius: 18)
                                )
                            }
                        }
                        .padding(.top, 6)
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)
            }
            Spacer(minLength: 0)
        }
        .focusEffectDisabled()
        .padding(.horizontal, 16)
        .padding(.vertical, CrestSpacing.medium)
        .frame(width: SidebarGeometry.width)
        .background(CrestBrandTheme.surface, in: RoundedRectangle(cornerRadius: SidebarGeometry.radius))
        .overlay { RoundedRectangle(cornerRadius: SidebarGeometry.radius).stroke(CrestBrandTheme.line, lineWidth: 0.5) }
        .sheet(
            isPresented: $showsSpaceEditor, onDismiss: { store.sidebarEditorPresented = false },
            content: {
                SpaceEditor(space: editingSpace, store: store) { showsSpaceEditor = false }
            })
    }

    private func dropTarget(_ title: String, placement: BrowserTab.Placement) -> some View {
        Text(title).font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity).frame(height: 32)
            .overlay {
                RoundedRectangle(cornerRadius: 16).strokeBorder(
                    CrestBrandTheme.line, style: StrokeStyle(lineWidth: 1, dash: [3]))
            }
            .modifier(BrowserDropArea(store: store, placement: placement))
    }

    private var pins: [BrowserTab] { store.activeSpace.tabs.filter { $0.placement == .pinned } }
    private var saved: [BrowserTab] { store.activeSpace.tabs.filter { $0.placement == .saved && $0.folderID == nil } }
    private var current: [BrowserTab] {
        store.activeSpace.tabs.filter { $0.placement == .current && $0.folderID == nil }
    }

    private var spaceSwitcher: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(store.session.spaces) { space in
                    Button {
                        store.selectSpace(space.id)
                    } label: {
                        Circle().fill(Color.space(space.color)).frame(width: 12, height: 12)
                            .padding(4)
                            .overlay {
                                if store.activeSpace.id == space.id {
                                    Circle().stroke(.primary.opacity(0.8), lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(space.name)
                    .contextMenu {
                        Button("New Space") { showEditor(nil) }
                        Button("Edit Space") { showEditor(space) }
                        Button("Delete Space", role: .destructive) { store.deleteSpace(space.id) }
                    }
                    .modifier(BrowserDropArea(store: store, spaceID: space.id))
                }
            }
            .padding(3)
        }
        .scrollIndicators(.hidden)
        .frame(width: min(CGFloat(store.session.spaces.count) * 28 + 4, 178), height: 24)
        .background(CrestColor.hover, in: Capsule())
        .contextMenu { Button("New Space") { showEditor(nil) } }
    }

    private var navigation: some View {
        HStack(alignment: .top, spacing: 4) {
            navigationButton("chevron.left", hint: "⌘[", enabled: store.activePage?.canGoBack == true) {
                store.activePage?.webView.goBack()
            }
            navigationButton("chevron.right", hint: "⌘]", enabled: store.activePage?.canGoForward == true) {
                store.activePage?.webView.goForward()
            }
            navigationButton(
                store.activePage?.isLoading == true ? "xmark" : "arrow.clockwise", hint: "⌘R",
                enabled: store.activePage != nil
            ) {
                guard let page = store.activePage else { return }
                if page.isLoading { page.webView.stopLoading() } else { page.webView.reload() }
            }
            Spacer(minLength: 0)
            navigationButton("magnifyingglass", hint: "⌘L") { store.presentAddress() }
            moreMenu
        }
        .padding(.top, CrestSpacing.extraSmall)
        .background(BrowserWindowTitleBarSurface())
    }

    private func navigationButton(_ symbol: String, hint: String, enabled: Bool = true, action: @escaping () -> Void)
        -> some View
    {
        VStack(spacing: 1) {
            Button(action: action) {
                BrowserChromeSymbolLabel(
                    systemName: symbol, pointSize: SidebarGeometry.navigationSymbolPointSize)
            }
            .buttonStyle(CrestChromeButtonStyle(controlSize: CGSize(width: 40, height: 40)))
            .disabled(!enabled)
            .accessibilityLabel(symbol == "magnifyingglass" ? "Address and Search" : symbol)
            BrowserShortcutHint(text: hint).opacity(enabled ? 1 : 0.4)
        }
    }

    private var moreMenu: some View {
        Menu {
            if let page = store.activePage {
                Label(
                    page.url?.scheme == "https" ? "Secure Connection" : "Site Information",
                    systemImage: page.url?.scheme == "https" ? "lock" : "info.circle")
                Button(page.isReaderMode ? "Exit Reader Mode" : "Reader Mode", systemImage: "doc.text") {
                    page.toggleReader()
                }
                Button("Translate Page", systemImage: "translate") { page.translationRequest &+= 1 }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Website Settings…", systemImage: "slider.horizontal.3") { store.siteSettingsPresented = true }
                Button("Developer Tools", systemImage: "curlybraces") { page.showDeveloperTools() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                Button("Copy Address", systemImage: "link") {
                    guard let url = page.url else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                Divider()
            }
            Button("New Private Space", systemImage: "eye.slash") { store.savePrivateSpace() }
            Button("New Folder", systemImage: "folder.badge.plus") { store.addFolder() }
            Menu("Live Folder") {
                Button("GitHub") {
                    store.addFolder(github: true)
                    store.integration(for: store.activeSpace.id).requestRefresh()
                }
            }
            Divider()
            Button("History", systemImage: "clock.arrow.circlepath") { store.utility = .history }.keyboardShortcut("y")
            Button("Archive", systemImage: "archivebox") { store.utility = .archive }
            Button("Downloads", systemImage: "arrow.down.circle") { store.utility = .downloads }.keyboardShortcut(
                "j", modifiers: [.command, .shift])
            Divider()
            Button("Settings…", systemImage: "gearshape") { store.openSettings() }.keyboardShortcut(",")
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 18))
                .frame(width: 40, height: 40)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .frame(width: 40, height: 40)
        .accessibilityLabel("Space and Website Options")
    }

    private func nowPlaying(_ page: BrowserPage) -> some View {
        HStack(spacing: 9) {
            Button {
                store.selectTab(page.id)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "waveform").frame(width: 20)
                    Text(page.mediaTitle.isEmpty ? page.title : page.mediaTitle).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button {
                page.toggleMedia()
            } label: {
                Image(systemName: page.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(CrestChromeButtonStyle())
        }
        .padding(.horizontal, 10).frame(height: SidebarGeometry.rowHeight)
        .crestHoverSurface(cornerRadius: 20, showsRestingSurface: true)
        .padding(.top, 6)
    }

    private func showEditor(_ space: BrowserSpace?) {
        editingSpace = space
        store.sidebarEditorPresented = true
        showsSpaceEditor = true
    }
}
