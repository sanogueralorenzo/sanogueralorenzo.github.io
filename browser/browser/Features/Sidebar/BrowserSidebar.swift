import SwiftUI

struct BrowserSidebar: View {
    let store: BrowserStore
    @State private var editingSpace: BrowserSpace?
    @State private var showsSpaceEditor = false

    @State private var resizeStart: CGFloat?

    var body: some View {
        VStack(spacing: SidebarGeometry.panelSpacing) {
            header
            navigation
            if let utility = store.utility {
                BrowserUtilityList(utility: utility, store: store)
                    .padding(SidebarGeometry.panelPadding)
                    .browserSidebarPanel()
            } else {
                BrowserSidebarSpacePager(store: store)
            }
        }
        .font(.system(size: 13))
        .background { BrowserSidebarFolderReconciler(store: store) }
        .focusEffectDisabled()
        .frame(width: store.sidebarWidth)
        .overlay(alignment: .trailing) { resizeHandle }
        .sheet(
            isPresented: $showsSpaceEditor, onDismiss: { store.sidebarEditorPresented = false },
            content: {
                SpaceEditor(space: editingSpace, store: store) { showsSpaceEditor = false }
            })
    }

    private var header: some View {
        HStack(spacing: SidebarGeometry.titlebarSpacing) {
            Spacer().frame(width: SidebarGeometry.titlebarLeadingSpace)
            BrowserSpaceSwitcher(store: store, edit: showEditor)
            Spacer(minLength: 0)
            moreMenu
        }
        .padding(.horizontal, SidebarGeometry.titlebarHorizontalInset)
        .frame(height: SidebarGeometry.titlebarHeight)
        .background(BrowserWindowTitleBarSurface())
    }

    private var resizeHandle: some View {
        Color.clear.frame(width: 6)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if resizeStart == nil { resizeStart = store.sidebarWidth }
                        store.isResizingSidebar = true
                        store.session.preferences.sidebarWidth = Double(
                            SidebarGeometry.clampedWidth((resizeStart ?? store.sidebarWidth) + value.translation.width))
                    }
                    .onEnded { _ in
                        resizeStart = nil
                        store.isResizingSidebar = false
                        store.changed()
                    }
            )
            .accessibilityLabel("Resize Sidebar")
            .accessibilityAdjustableAction { direction in
                let delta: CGFloat = direction == .increment ? 10 : -10
                store.updatePreferences {
                    $0.sidebarWidth = Double(SidebarGeometry.clampedWidth(store.sidebarWidth + delta))
                }
            }
    }

    private var navigation: some View {
        let loading = store.activePage?.isLoading == true
        return VStack(spacing: 0) {
            HStack(spacing: 2) {
                navigationButton("chevron.left", label: "Back", hint: "⌘[", enabled: store.activePage?.canGoBack == true) {
                    store.activePage?.webView.goBack()
                }
                navigationButton("chevron.right", label: "Forward", hint: "⌘]", enabled: store.activePage?.canGoForward == true) {
                    store.activePage?.webView.goForward()
                }
                navigationButton(
                    loading ? "xmark" : "arrow.clockwise", label: loading ? "Stop Loading" : "Reload", hint: "⌘R",
                    enabled: store.activePage != nil
                ) {
                    guard let page = store.activePage else { return }
                    if page.isLoading { page.stopLoading() } else { page.webView.reload() }
                }
                addressButton
            }
            .padding(5)
            if !store.activeSpace.isPrivate, let playing = store.playingPage { nowPlaying(playing) }
        }
        .background(BrowserWindowTitleBarSurface())
        .browserSidebarPanel()
    }

    private var addressButton: some View {
        let url = store.activePage?.url ?? store.selectedTab?.url
        return Button {
            store.presentAddress()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text(url?.host ?? url?.absoluteString ?? "Search or enter URL")
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: BrowserLayout.minimumHitTarget, alignment: .leading)
            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(BrowserChromeButtonStyle(controlSize: nil, cornerRadius: 8))
        .accessibilityLabel("Address and search")
        .help("Address and search (⌘L)")
    }

    private func navigationButton(
        _ symbol: String, label: String, hint: String, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            BrowserChromeSymbolLabel(systemName: symbol, pointSize: SidebarGeometry.navigationSymbolPointSize)
        }
        .buttonStyle(BrowserChromeButtonStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
        .help("\(label) (\(hint))")
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
            Button("New Tab", systemImage: "plus") { store.presentAddress(newTab: true) }.keyboardShortcut("t")
            Button("New Private Space", systemImage: "eye.slash") { store.savePrivateSpace() }
            Button("New Folder", systemImage: "folder.badge.plus") { store.addFolder() }
            Menu("Live Folder") {
                Button("GitHub") {
                    guard store.addFolder(github: true) != nil else { return }
                    store.integration(for: store.activeSpace.id).requestRefresh()
                }
            }
            .disabled(store.activeSpace.isPrivate)
            Divider()
            if store.utility != nil { Button("Back to Tabs", systemImage: "sidebar.left") { store.utility = nil } }
            Button("History", systemImage: "clock.arrow.circlepath") { store.presentUtility(.history) }
                .keyboardShortcut("y")
            Button("Archive", systemImage: "archivebox") { store.presentUtility(.archive) }
            Button("Downloads", systemImage: "arrow.down.circle") { store.presentUtility(.downloads) }.keyboardShortcut(
                "j", modifiers: [.command, .shift])
            Divider()
            Button("Settings…", systemImage: "gearshape") { store.openSettings() }.keyboardShortcut(",")
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 16))
                .frame(width: BrowserLayout.minimumHitTarget, height: BrowserLayout.minimumHitTarget)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .frame(width: BrowserLayout.minimumHitTarget, height: BrowserLayout.minimumHitTarget)
        .accessibilityLabel("Space and Website Options")
    }

    private func nowPlaying(_ page: BrowserPage) -> some View {
        HStack(spacing: 0) {
            Button {
                store.selectTab(page.id)
            } label: {
                HStack(spacing: 8) {
                    if let data = page.favicon, let icon = NSImage(data: data) {
                        Image(nsImage: icon).resizable().scaledToFit().frame(width: 22, height: 22).frame(width: 28)
                    } else {
                        Image(systemName: "music.note").frame(width: 28)
                    }
                    Text(page.mediaTitle.isEmpty ? page.title : page.mediaTitle).lineLimit(1)
                }
                .padding(.leading, 9).padding(.trailing, 4)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Show tab playing \(page.mediaTitle)")
            if page.mediaActions.contains("previoustrack") {
                mediaButton(page, action: "previoustrack", symbol: "backward.fill", label: "Previous Track")
            }
            mediaButton(
                page, action: page.isPlaying ? "pause" : "play", symbol: page.isPlaying ? "pause.fill" : "play.fill",
                label: page.isPlaying ? "Pause" : "Play")
            if page.mediaActions.contains("nexttrack") {
                mediaButton(page, action: "nexttrack", symbol: "forward.fill", label: "Next Track")
            }
        }
        .padding(.trailing, 6).frame(height: SidebarGeometry.rowHeight)
        .browserHoverSurface(cornerRadius: 20, showsRestingSurface: true)
        .padding(.horizontal, 5).padding(.bottom, 5)
        .accessibilityElement(children: .contain).accessibilityLabel("Now Playing")
        .contextMenu {
            Button(page.mediaIsMuted ? "Unmute" : "Mute") {
                page.performMediaAction(page.mediaIsMuted ? "unmute" : "mute")
            }
            Button("Hide Now Playing") { page.nowPlayingHidden = true }
        }
    }

    private func mediaButton(_ page: BrowserPage, action: String, symbol: String, label: String) -> some View {
        Button {
            page.performMediaAction(action)
        } label: {
            Image(systemName: symbol).font(.system(size: 12))
        }
        .buttonStyle(BrowserChromeButtonStyle(controlSize: CGSize(width: 28, height: 28), cornerRadius: 14))
        .accessibilityLabel(label)
    }

    private func showEditor(_ space: BrowserSpace?) {
        editingSpace = space
        store.sidebarEditorPresented = true
        showsSpaceEditor = true
    }
}
