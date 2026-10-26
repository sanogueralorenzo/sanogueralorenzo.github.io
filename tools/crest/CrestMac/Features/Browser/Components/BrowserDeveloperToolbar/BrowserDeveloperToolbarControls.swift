import SwiftUI

struct BrowserDeveloperAddressField: View {
    @Binding var address: String
    let navigate: @MainActor () -> Void

    var body: some View {
        TextField("Full URL", text: $address)
            .textFieldStyle(.plain)
            .font(.system(.callout, design: .monospaced).weight(.medium))
            .lineLimit(1)
            .frame(minWidth: 0, maxWidth: .infinity)
            .layoutPriority(-1)
            .onSubmit(navigate)
            .accessibilityLabel("Developer URL")
            .accessibilityIdentifier("developer-url-field")
    }
}

struct BrowserDeveloperSiteSettingsControl: View {
    let page: BrowserPage
    let permissionCenter: BrowserSitePermissionCenter
    @Binding var isPresented: Bool
    @Binding var permissionsExpansion: Bool

    var body: some View {
        BrowserDeveloperToolbarButton(
            label: "Site Settings",
            systemImage: "info.circle.fill",
            isActive: isPresented,
            action: { isPresented.toggle() }
        )
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            BrowserSiteSettingsContent(
                page: page,
                permissionCenter: permissionCenter,
                permissionsExpansion: $permissionsExpansion
            )
            .padding(14)
            .frame(width: 300)
        }
    }
}

struct BrowserDeveloperInspectorControls: View {
    let page: BrowserPage

    var body: some View {
        HStack(spacing: BrowserDeveloperToolbarMetrics.itemSpacing) {
            BrowserDeveloperToolbarButton(
                label: "Toggle Console",
                systemImage: "apple.terminal",
                isActive: page.developerPanel == .console,
                action: { page.toggleDeveloperPanel(.console) }
            )
            BrowserDeveloperToolbarButton(
                label: "Toggle Network Panel",
                systemImage: "network",
                isActive: page.developerPanel == .network,
                action: { page.toggleDeveloperPanel(.network) }
            )
            BrowserDeveloperToolbarButton(
                label: "Inspect Element",
                systemImage: "scope",
                isActive: page.developerPanel == .elements,
                action: { page.toggleDeveloperPanel(.elements) }
            )
        }
    }
}
