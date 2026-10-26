import SwiftUI

struct BrowserDeveloperToolbar: View {
    let page: BrowserPage
    let browser: BrowserStore
    let pages: BrowserPagePool
    let permissionCenter: BrowserSitePermissionCenter

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var address = ""
    @State private var showsSiteSettings = false

    var body: some View {
        BrowserPageToolbarSurface(label: "Developer Toolbar", identifier: "developer-toolbar") {
            controls
        } background: {
            BrowserDeveloperToolbarBackground(isOpaque: reduceTransparency)
        }
        .onAppear(perform: synchronizeAddress)
        .onChange(of: page.live.displayURL) { _, _ in synchronizeAddress() }
    }

    private var controls: some View {
        HStack(spacing: BrowserDeveloperToolbarMetrics.itemSpacing) {
            BrowserDeveloperViewportMenu(page: page)
            BrowserDeveloperToolbarDivider()
            BrowserDeveloperSiteSettingsControl(
                page: page,
                permissionCenter: permissionCenter,
                isPresented: $showsSiteSettings
            )
            BrowserDeveloperAddressField(
                address: $address,
                navigate: navigate
            )
            ViewThatFits(in: .horizontal) {
                actionControls.fixedSize(horizontal: true, vertical: false)
                overflowMenu
            }
        }
    }

    private var actionControls: some View {
        HStack(spacing: BrowserDeveloperToolbarMetrics.itemSpacing) {
            BrowserDeveloperToolbarButton(
                label: "Copy Link",
                systemImage: "link",
                action: { page.copyPageLink() }
            )
            BrowserDeveloperToolbarDivider()
            BrowserDeveloperInspectorControls(page: page)
        }
    }

    private var overflowMenu: some View {
        Menu {
            Button("Copy Link", systemImage: "link", action: { page.copyPageLink() })
            Divider()
            Button("Toggle Console", systemImage: "apple.terminal") { page.toggleDeveloperPanel(.console) }
            Button("Toggle Network Panel", systemImage: "network") { page.toggleDeveloperPanel(.network) }
            Button("Inspect Element", systemImage: "scope") { page.toggleDeveloperPanel(.elements) }
        } label: {
            Image(systemName: "ellipsis")
                .frame(
                    width: BrowserDeveloperToolbarMetrics.buttonSize, height: BrowserDeveloperToolbarMetrics.buttonSize)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Developer Tools")
        .accessibilityIdentifier("developer-tools-overflow")
        .help("Developer Tools")
    }

    private func synchronizeAddress() {
        address = page.live.displayURL?.absoluteString ?? ""
    }

    /// Loads what the person typed, which the core resolves by the Space's
    /// address rules.
    private func navigate() {
        let input = address
        if pages.activePage === page {
            browser.navigateSelectedTab(to: input)
            guard pages.navigate(to: input) else { return }
        } else {
            guard page.corePage.navigate(to: input) else { return }
        }
        synchronizeAddress()
    }
}
