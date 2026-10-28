import SwiftUI

struct BrowserSidebar: View {
    let store: BrowserStore
    let cornerRadius: CGFloat
    @State private var editingSpace: BrowserSpace?
    @State private var showsSpaceEditor = false

    @State private var resizeStart: CGFloat?
    @State private var listHovered = false
    @State private var listHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    .onScrollGeometryChange(for: CGFloat.self) {
                        $0.contentOffset.y
                    } action: { old, new in
                        store.sidebarReorder.scroll(by: old - new, in: store)
                    }
                    .onHover { listHovered = $0 }
                }
            }
        }
        .font(.system(size: 13))
        .focusEffectDisabled()
        .animation(LeanMotion.collection.unlessReducingMotion(reduceMotion), value: store.activeSpace.orderedSidebarIDs)
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

    private var tabRows: some View {
        VStack(spacing: 2) {
            BrowserSidebarList(store: store, placement: .saved)
            if store.isDragging { dropTarget("Saved Tabs", placement: .saved) }
            if store.activeSpace.tabs.contains(where: { $0.placement == .current })
                || store.activeSpace.folders.contains(where: { $0.parentID == nil && $0.placement == .current })
            {
                currentDivider
            }
            BrowserSidebarList(store: store, placement: .current)
            if store.isDragging { dropTarget("Current Tabs", placement: .current) }
            newTab
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var pinnedTabs: some View {
        if !pins.isEmpty || store.owner.sidebarLift != nil {
            BrowserPinnedTabSlotLayout(
                projection: store.sidebarReorder.pinnedLayout(
                    in: store.activeSpace, width: store.sidebarWidth - 32)
            ) {
                ForEach(pins) { BrowserSidebarItem(tab: $0, store: store, pinned: true) }
                RoundedRectangle(cornerRadius: 20).fill(.primary.opacity(0.035))
                    .opacity(store.sidebarReorder.target?.placement == .pinned ? 1 : 0)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .modifier(BrowserDropArea(store: store, placement: .pinned))
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .animation(LeanMotion.dragSource.unlessReducingMotion(reduceMotion), value: store.sidebarReorder.target)
            .animation(
                LeanMotion.dragSource.unlessReducingMotion(reduceMotion), value: store.owner.sidebarLift?.rootIDs)
        }
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
        }.frame(height: 28)
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

    private func dropTarget(_ title: String, placement: BrowserTab.Placement) -> some View {
        Text(title).font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity).frame(height: 32)
            .overlay {
                RoundedRectangle(cornerRadius: 16).strokeBorder(
                    LeanBrandTheme.line, style: StrokeStyle(lineWidth: 1, dash: [3]))
            }
            .modifier(BrowserDropArea(store: store, placement: placement))
    }

    private var pins: [BrowserTab] { store.activeSpace.pinnedTabs }
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
