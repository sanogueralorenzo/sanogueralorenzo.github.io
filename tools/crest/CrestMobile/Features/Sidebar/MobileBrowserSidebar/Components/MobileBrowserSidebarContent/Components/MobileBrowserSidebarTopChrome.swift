import SwiftUI

struct MobileBrowserSidebarTopChrome: View {
    @Environment(\.mobileBrowserControlPlacement) private var controlPlacement
    let configuration: MobileBrowserSidebarContentConfiguration

    var body: some View {
        if configuration.utilityPresentationStyle == .inline {
            if controlPlacement.movesControlsToToolbar {
                // The strip's controls are toolbar items; the address field
                // leads, held off the sidebar's top edge as it is off its sides.
                Color.clear
                    .frame(height: BrowserSidebarMetrics.layerInset)
                    .accessibilityHidden(true)
                    .toolbar { navigationToolbarItems }
            } else {
                BrowserSidebarNavigationControls(
                    port: navigationPort,
                    capabilities: configuration.context.capabilities,
                    hidesUnavailableForwardControl: true
                ) {
                    pageActionsMenu()
                }
            }

            if let utilitySurface = configuration.context.utilityPresentation
                .surface
            {
                BrowserUtilitySearchToolbar(
                    surface: utilitySurface,
                    searchText: configuration.context.utilitySearchText,
                    filter: configuration.context.utilityFilter,
                    morphNamespace: configuration.compactChromeNamespace,
                    morph: .utilitySearch(spaceID: selectedSpaceID),
                    clearHistory: confirmClearHistory
                )
                .padding(.horizontal, BrowserSidebarMetrics.layerInset)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                BrowserSidebarAddressField(
                    configuration: addressConfiguration,
                    fieldContextMenu: {
                        if let pageActions = selectedPageActions,
                            pageActions.isAvailable,
                            !configuration.isAddressEditing.wrappedValue
                        {
                            MobilePageActionsContent(
                                browser: configuration.context.browser,
                                pages: pageActions
                            )
                            .tint(.primary)
                        }
                    }
                )
                .padding(.horizontal, BrowserSidebarMetrics.layerInset)
                .padding(.bottom, 4)
            }
        }

        if configuration.showsCompactAddressBar {
            GlassEffectContainer(spacing: 0) {
                MobileCompactNewTabPrompt(
                    namespace: configuration.compactChromeNamespace,
                    geometryID: configuration.context.browser
                        .selectedSpaceID,
                    transitionEnded: configuration.compactTransitionEnded,
                    openNewTab: configuration.openNewTab
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }

    /// The strip's controls as items in the side toolbar's top group, in the
    /// strip's order.
    @ToolbarContentBuilder
    private var navigationToolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            MobileHistoryToolbarControl(direction: .back, port: navigationPort)
            if navigationPort.canGoForward() {
                MobileHistoryToolbarControl(direction: .forward, port: navigationPort)
            }
            // A system button, which the bar can stand on end; the strip's
            // reload control is a custom view the bar keeps horizontal.
            Button(
                navigationPort.isLoading() ? "Stop" : "Reload",
                systemImage: navigationPort.isLoading() ? "xmark" : "arrow.clockwise",
                action: navigationPort.reloadOrStop
            )
            .disabled(!navigationPort.hasActivePage())
            .contextMenu {
                if navigationPort.activeURL()?.isLocalDevelopmentAddress == true {
                    Button(
                        "Reload (Ignore Cache)",
                        systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                        action: navigationPort.reloadFromOrigin
                    )
                    Button("Clear Cookies and Reload", systemImage: BrowsingDataCategory.siteData.symbol ?? "trash") {
                        Task { await navigationPort.clearCookiesAndReload() }
                    }
                }
            }
            .accessibilityIdentifier("reload-control")
            pageActionsMenu(isToolbarItem: true)
        }
    }

    @ViewBuilder
    private func pageActionsMenu(isToolbarItem: Bool = false) -> some View {
        if let pageActions = selectedPageActions,
            pageActions.isAvailable
        {
            MobilePageActionsMenu(
                browser: configuration.context.browser,
                pages: pageActions,
                systemImage: "ellipsis.circle",
                isToolbarItem: isToolbarItem
            )
            .font(.system(size: 17, weight: .medium))
        } else {
            Button(
                "Page Actions",
                systemImage: "ellipsis.circle",
                action: {}
            )
            .disabled(true)
            .font(.system(size: 17, weight: .medium))
        }
    }

    private var navigationPort: BrowserSidebarNavigationPort {
        BrowserSidebarNavigationPort(
            pageActions: selectedPageActions,
            showHistory: configuration.context.chromeActions.presentHistory
        )
    }

    /// `hasResidentPage` stays off: the compact field has no live-site controls
    /// to hand its leading slot, so the glyph there belongs to editing alone.
    private var addressConfiguration: BrowserSidebarAddressFieldConfiguration {
        BrowserSidebarAddressFieldConfiguration(
            text: configuration.address,
            isEditing: configuration.isAddressEditing,
            isSecure: displayedURL?.scheme?.lowercased() == "https",
            progress: selectedPageActions?.activePage?.estimatedProgress ?? 0,
            isLoading: selectedPageActions?.activePage?.live.isLoading == true,
            hasResidentPage: false,
            capabilities: configuration.context.capabilities,
            activate: configuration.activateAddress,
            submit: configuration.submitAddress,
            morphNamespace: configuration.compactChromeNamespace,
            spaceID: selectedSpaceID,
            commandPaletteHandoff: configuration.commandPaletteHandoff,
            branding: configuration.context.browser.shownSpace.map(\.settings.look)
        )
    }

    private var selectedPageActions: MobileSelectedPageActionPort? {
        MobileSelectedPageActionPort(
            browser: configuration.context.browser,
            pages: configuration.pages,
            spaceAccess: configuration.context.spaceAccess
        )
    }

    private var displayedURL: URL? {
        selectedPageActions?.activeURL
            ?? configuration.context.browser.shownTab?.url.flatMap(URL.init(string:))
    }

    /// The chrome sits above the pager, so the field and the toolbar belong
    /// to the selected Space.
    private var selectedSpaceID: UUID {
        configuration.context.browser.selectedSpaceID
    }

    /// The toolbar sits above the pager, so the Space it clears is the selected
    /// one. The root refuses the request unless that Space is still reachable.
    private func confirmClearHistory() {
        guard let space = configuration.context.browser.shownSpace else {
            return
        }
        configuration.context.confirmClearHistory(space)
    }
}
