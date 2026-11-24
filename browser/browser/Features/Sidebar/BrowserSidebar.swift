import SwiftUI

struct BrowserSidebar: View {
    let store: BrowserStore
    @State private var editingSpace: BrowserSpace?
    @State private var showsSpaceEditor = false

    @State private var resizeStart: CGFloat?

    var body: some View {
        VStack(spacing: SidebarGeometry.panelSpacing) {
            windowControls
            VStack(spacing: SidebarGeometry.panelSpacing) {
                BrowserSpaceSwitcher(store: store, edit: showEditor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                navigation
                Divider()
                if !store.activeSpace.isPrivate, let page = store.playingPage {
                    BrowserNowPlaying(page: page) { store.selectTab(page.id) }
                }
                if let utility = store.utility {
                    BrowserUtilityList(utility: utility, store: store)
                } else {
                    BrowserSidebarSpacePager(store: store)
                }
            }
            .padding(.horizontal, SidebarGeometry.contentInset)
            .padding(.bottom, SidebarGeometry.panelSpacing)
        }
        .font(.system(size: 13))
        .background { BrowserSidebarFolderReconciler(store: store) }
        .focusEffectDisabled()
        .frame(width: store.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            let shape = RoundedRectangle(cornerRadius: SidebarGeometry.backdropRadius)
            shape.fill(BrowserBrandTheme.sidebarBackdrop)
                .overlay { shape.strokeBorder(BrowserBrandTheme.line, lineWidth: 0.75) }
        }
        .overlay(alignment: .trailing) { resizeHandle }
        .sheet(
            isPresented: $showsSpaceEditor, onDismiss: { store.sidebarEditorPresented = false },
            content: {
                SpaceEditor(space: editingSpace, store: store) { showsSpaceEditor = false }
            })
    }

    private var windowControls: some View {
        HStack(spacing: SidebarGeometry.titlebarSpacing) {
            if !store.isFullScreen { Color.clear.frame(width: SidebarGeometry.windowControlsWidth) }
            Button {
                store.sidebarDocked.toggle()
            } label: {
                Image(systemName: store.sidebarDocked ? "rectangle.leftthird.inset.filled" : "sidebar.left")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(BrowserChromeButtonStyle())
            .accessibilityLabel("Keep Sidebar Open")
            .accessibilityValue(store.sidebarDocked ? "On" : "Off")
            .accessibilityIdentifier("sidebar-dock")
            .help(store.sidebarDocked ? "Switch to Hover Sidebar" : "Keep Sidebar Open")
            Spacer(minLength: 0)
            moreMenu
        }
        .padding(.horizontal, SidebarGeometry.titlebarHorizontalInset)
        .frame(height: SidebarGeometry.titlebarHeight)
        .background(BrowserWindowTitleBarSurface())
        .environment(\.layoutDirection, .leftToRight)
    }

    private var resizeHandle: some View {
        Color.clear.frame(width: 6)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
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
        return HStack(spacing: 6) {
            HStack(spacing: 0) {
                navigationButton(
                    "chevron.left", label: "Back", hint: "⌘[", enabled: store.activePage?.canGoBack == true
                ) {
                    store.activePage?.webView.goBack()
                }
                Rectangle().fill(BrowserBrandTheme.line).frame(width: 1, height: 14).accessibilityHidden(true)
                navigationButton(
                    "chevron.right", label: "Forward", hint: "⌘]", enabled: store.activePage?.canGoForward == true
                ) {
                    store.activePage?.webView.goForward()
                }
            }
            .background(.quaternary, in: .rect(cornerRadius: 8))
            navigationButton(
                loading ? "xmark" : "arrow.clockwise", label: loading ? "Stop Loading" : "Reload", hint: "⌘R",
                enabled: store.activePage != nil, showsRestingFill: true
            ) {
                guard let page = store.activePage else { return }
                if page.isLoading { page.stopLoading() } else { page.webView.reload() }
            }
            addressButton
        }
    }

    private var addressButton: some View {
        let url = store.activePage?.url ?? store.selectedTab?.url
        return Button {
            store.presentAddress()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text(url?.host ?? url?.absoluteString ?? "Search")
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: BrowserLayout.minimumHitTarget, alignment: .leading)
            .background(.quaternary, in: .rect(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(BrowserChromeButtonStyle(controlSize: nil, cornerRadius: 8))
        .accessibilityLabel("Address and search")
        .help("Address and search (⌘L)")
    }

    private func navigationButton(
        _ symbol: String, label: String, hint: String, enabled: Bool, showsRestingFill: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            BrowserChromeSymbolLabel(systemName: symbol, pointSize: SidebarGeometry.navigationSymbolPointSize)
        }
        .buttonStyle(BrowserChromeButtonStyle(cornerRadius: 8, showsRestingFill: showsRestingFill))
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

    private func showEditor(_ space: BrowserSpace?) {
        editingSpace = space
        store.sidebarEditorPresented = true
        showsSpaceEditor = true
    }
}
