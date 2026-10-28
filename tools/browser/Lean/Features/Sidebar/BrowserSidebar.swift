import SwiftUI

struct BrowserSidebar: View {
    let store: BrowserStore
    let cornerRadius: CGFloat
    @State private var editingSpace: BrowserSpace?
    @State private var showsSpaceEditor = false

    @State private var resizeStart: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 70)
                BrowserSpaceSwitcher(store: store, edit: showEditor)
            }
            .padding(.horizontal, SidebarGeometry.titlebarHorizontalInset)
            .frame(height: SidebarGeometry.titlebarHeight)
            .background(BrowserWindowTitleBarSurface())
            navigation.padding(.bottom, 4)
            if !store.activeSpace.isPrivate, let playing = store.playingPage { nowPlaying(playing) }
            if let utility = store.utility {
                BrowserUtilityList(utility: utility, store: store).padding(.horizontal, 16)
            } else {
                BrowserSidebarSpacePager(store: store)
            }
        }
        .font(.system(size: 13))
        .background { BrowserSidebarFolderReconciler(store: store) }
        .focusEffectDisabled()
        .frame(width: store.sidebarWidth)
        .background(LeanBrandTheme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(
                LeanBrandTheme.line, lineWidth: 0.75
            )
            .allowsHitTesting(false)
        }
        .overlay(alignment: .trailing) { resizeHandle }
        .sheet(
            isPresented: $showsSpaceEditor, onDismiss: { store.sidebarEditorPresented = false },
            content: {
                SpaceEditor(space: editingSpace, store: store) { showsSpaceEditor = false }
            })
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
        HStack(alignment: .top, spacing: 0) {
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
            moreMenu.offset(y: -8)
        }
        .padding(.horizontal, 16)
        .background(BrowserWindowTitleBarSurface())
    }

    private func navigationButton(_ symbol: String, hint: String, enabled: Bool = true, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            VStack(spacing: 2) {
                BrowserChromeSymbolLabel(systemName: symbol, pointSize: SidebarGeometry.navigationSymbolPointSize)
                BrowserShortcutHint(text: hint)
            }.frame(width: 40, height: 40)
        }
        .buttonStyle(LeanChromeButtonStyle(controlSize: nil))
        .disabled(!enabled)
        .accessibilityLabel(
            symbol == "magnifyingglass"
                ? "Address and search"
                : symbol == "chevron.left"
                    ? "Back" : symbol == "chevron.right" ? "Forward" : symbol == "xmark" ? "Stop Loading" : "Reload")
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
            Image(systemName: "ellipsis").font(.system(size: 18))
                .frame(width: 40, height: 40)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .frame(width: 40, height: 40)
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
        .leanHoverSurface(cornerRadius: 20, showsRestingSurface: true)
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
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
        .buttonStyle(LeanChromeButtonStyle(controlSize: CGSize(width: 28, height: 28), cornerRadius: 14))
        .accessibilityLabel(label)
    }

    private func showEditor(_ space: BrowserSpace?) {
        editingSpace = space
        store.sidebarEditorPresented = true
        showsSpaceEditor = true
    }
}
