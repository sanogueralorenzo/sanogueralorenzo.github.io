import SwiftUI

struct MobileBrowserSidebarBottomChrome: View {
    @Environment(\.mobileBrowserControlPlacement) private var controlPlacement
    let configuration: MobileBrowserSidebarContentConfiguration

    private var sidebarOnRight: Bool { BrowserDeviceAppearanceStore.shared.sidebarOnRight }

    var body: some View {
        if controlPlacement.movesControlsToToolbar {
            // The controls are toolbar items, so the chrome holds no room under
            // the tabs for them.
            Color.clear
                .frame(height: 0)
                .accessibilityHidden(true)
                .toolbar { toolbarItems }
        } else {
            capsule
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            if configuration.showsSidebarToggle {
                sidebarToggle
            }
            if showsSpaceActions {
                MobileSpaceActionButtons(
                    browser: configuration.context.browser,
                    pages: configuration.pages,
                    utilityPresentationStyle: configuration.utilityPresentationStyle,
                    configuration: configuration.spaceActionsConfiguration
                )
            }
        }
    }

    private var capsule: some View {
        ZStack {
            actions

            if configuration.showsSidebarToggle {
                HStack {
                    sidebarToggle
                        .buttonStyle(.plain)
                        .controlSize(.large)
                        .padding(4)
                        .glassEffect(.regular, in: .capsule)
                        .fixedSize(horizontal: true, vertical: false)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: 60)
            }
        }
        .modifier(
            SpaceForegroundBlend(
                spaces: configuration.context.availableSpaces,
                selectedSpaceID: configuration.context.browser.shownSpace?.id)
        )
        .padding(
            .bottom,
            configuration.sidebarIsDocked
                ? configuration.reservesBottomChromeInset
                    ? 0
                    : BrowserChromeLayout.pageFrameInset
                : MobileBrowserRootLayout.floatingSidebarBottomChromeInset
        )
    }

    private var sidebarToggle: some View {
        Button(action: configuration.toggleSidebar) {
            MobileSpaceUtilityButtonLabel(
                systemImage: sidebarOnRight ? "sidebar.right" : "sidebar.left")
        }
        .help(sidebarToggleTitle)
        .accessibilityLabel(sidebarToggleTitle)
        .accessibilityIdentifier("browser-sidebar-toggle")
    }

    private var showsSpaceActions: Bool {
        configuration.context.browser.showsSelectedSpaceActions(
            accessController: configuration.context.spaceAccess)
    }

    @ViewBuilder
    private var actions: some View {
        if holdsReservedSpace {
            reservedSpace
        } else {
            if showsSpaceActions {
                MobileSpaceActions(
                    browser: configuration.context.browser,
                    pages: configuration.pages,
                    utilityPresentationStyle:
                        configuration.utilityPresentationStyle,
                    configuration: configuration.spaceActionsConfiguration
                )
                .transition(.opacity)
            } else {
                reservedSpace
            }
        }
    }

    /// Whether the chrome only holds its reserved inset open, its controls
    /// being off screen.
    private var holdsReservedSpace: Bool {
        configuration.reservesBottomChromeInset && !configuration.showsBottomSpaceSwitcher
    }

    private var reservedSpace: some View {
        Color.clear
            .frame(height: 60)
            .accessibilityHidden(true)
    }

    private var sidebarToggleTitle: LocalizedStringKey {
        if configuration.sidebarToggleUndocks {
            return "Undock Sidebar"
        }
        return configuration.sidebarIsDocked
            ? "Hide Sidebar"
            : "Dock Sidebar"
    }
}
