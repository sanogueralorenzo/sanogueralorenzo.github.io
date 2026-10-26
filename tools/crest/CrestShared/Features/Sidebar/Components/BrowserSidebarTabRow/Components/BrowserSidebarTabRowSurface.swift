import SwiftUI
import UniformTypeIdentifiers

/// Everything wrapped around a tab row's content: its band, its selection and
/// hover treatment, and every gesture the row answers.
///
/// Two things about this chain are load-bearing and invisible in the code.
///
/// **The lift is armed before the menu.** `browserTabDraggable` must stay above
/// `contextMenu`. On a touch shell the lift *is* drag-and-drop —
/// `UIContextMenuInteraction` cancels any gesture that competes with it, so
/// drag-and-drop is the only path the system arbitrates against a menu — and the
/// row is the view that carries both. Move the menu under the drag source and
/// holding a row raises the menu with nothing left to pull.
///
/// **A row claims at most one promotion anchor.** The pairing below is an
/// either/or: `browserTabPromotionDestination` for a shell that grows a surface
/// out of the row through matched geometry, `BrowserPlatformTabPromotionSource`
/// for one that pushes a page with the system's navigation zoom. Both anchor the
/// same identity, and both are presentation transforms over the exact view the
/// drag interaction lifts. Two of them, or one with no partner to pair with, and
/// the lift stops starting — which is what
/// `BrowserInteractionCapabilities.usesMatchedGeometryPromotionDestination` and
/// `BrowserInteractionCapabilities.pairsRowWithPromotedSurface` exist to keep
/// from happening.
struct BrowserSidebarTabRowSurface: ViewModifier {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction

    let configuration: BrowserSidebarTabRowConfiguration
    let interaction: BrowserSidebarTabRowInteractionContext

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var tabScale: Double { BrowserDeviceAppearanceStore.shared.tabScale }

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .frame(minHeight: minHeight)
            .contentShape(.rect)
            .modifier(
                BrowserSidebarTabRowAppearance(
                    configuration: configuration,
                    isHovering: interaction.isHovering
                )
            )
            .padding(
                .vertical,
                BrowserSidebarDensity(tabScale).rowSeparation(
                    hasBorders: BrowserDeviceAppearanceStore.shared.tabs.borders == .all) / 2
            )
            .browserTabPromotionDestination(
                id: configuration.promotionID,
                in: configuration.promotionNamespace,
                isActive: usesMatchedGeometryPromotion
            )
            .modifier(
                BrowserPlatformTabPromotionSourceModifier(
                    id: configuration.promotionID,
                    namespace: configuration.promotionNamespace,
                    usesNativeNavigationTransition:
                        configuration.capabilities.usesNativeNavigationTransition,
                    isEnabled: configuration.isPromotionSource
                )
            )
            .padding(.horizontal, configuration.surfaceHorizontalInset)
            .modifier(
                BrowserTabSelectionTarget(
                    tabID: configuration.tab.id, browser: configuration.browser,
                    assignment: BrowserSpaceRuntimeAssignment(
                        spaceID: configuration.spaceID, profileID: configuration.profileID),
                    isEnabled: configuration.isAvailableForDisplay && !interaction.isRenaming)
            )
            .contentShape(.rect)
            .onHover { interaction.isHovering.wrappedValue = $0 }
            .modifier(
                BrowserPlatformRowAuxiliaryClickModifier(
                    perform: interaction.dismissFromAuxiliaryClick
                )
            )
            .browserTabDraggable(
                tab: configuration.tab,
                favicons: configuration.favicons,
                profileID: configuration.profileID,
                spaceID: configuration.spaceID,
                dragState: sidebarInteraction.tabDragState,
                reorder: BrowserSidebarReorderContext(
                    browser: configuration.browser,
                    spaceAccess: configuration.spaceAccess,
                    state: sidebarInteraction.sidebarReorderState
                ),
                parentSplitGroupID: configuration.isSplitGroupMember ? configuration.tab.splitGroupID : nil,
                isEnabled: !interaction.isRenaming
                    && configuration.isAvailableForDisplay
                    && configuration.capabilities.supportsOrganization,
                requiresSelectedSpace: true
            )
            .browserSidebarReorderZone(
                .currentTab(configuration.tab.id),
                state: sidebarInteraction.sidebarReorderState,
                isActive: configuration.tab.splitGroupID == nil
                    && !configuration.tab.placement.isDurable
                    && configuration.tab.folderID == nil
                    && configuration.isAvailableForDisplay,
                requiresSelectedSpace: true
            )
            .overlay {
                BrowserFolderNestDropHighlight(
                    state: sidebarInteraction.sidebarReorderState, target: .currentTab(configuration.tab.id))
            }
            .crestCollectionItemTransition()
            .accessibilityElement(children: .contain)
            .contextMenu {
                if configuration.capabilities.supportsOrganization { organizationMenu }
            }
            .onChange(of: interaction.isTitleFocused.wrappedValue) { _, focused in
                if !focused, interaction.isRenaming {
                    interaction.commitTitle()
                }
            }
    }

    /// Opening the menu ends any drag the same row had started. The lift and
    /// the long press are the same gesture up to the moment one of them wins,
    /// and a menu that opens over a live drag leaves the list mid-reorder.
    private var organizationMenu: some View {
        BrowserTabOrganizationMenu(
            tab: configuration.tab,
            context: configuration.context,
            assignment: configuration.runtimeAssignment,
            isLoaded: configuration.isLoaded,
            renameTab: interaction.beginRenaming,
            changeIcon: interaction.beginChangingIcon
        )
        .tint(.primary)
        .onAppear {
            sidebarInteraction.tabDragState.contextMenuDidOpen(
                for: configuration.runtimeAssignment
            )
            // Both states, because the two lifts are different machines: the
            // pointer drag reports through `tabDragState`, and the touch lift
            // through the reorder state, which has no session left to hear
            // from once this menu has the press.
            sidebarInteraction.sidebarReorderState
                .yieldToCompetingInteraction()
        }
        .onDisappear {
            sidebarInteraction.tabDragState.contextMenuDidClose(
                for: configuration.runtimeAssignment
            )
        }
    }

    private var minHeight: CGFloat {
        let base = configuration.capabilities.rowMinHeight(dynamicTypeSize: dynamicTypeSize)
        return BrowserSidebarDensity(dynamicTypeSize.isAccessibilitySize ? max(1, tabScale) : tabScale).rowHeight(
            base: base, touch: configuration.capabilities.supportsTouch)
    }

    private var usesMatchedGeometryPromotion: Bool {
        configuration.capabilities.usesMatchedGeometryPromotionDestination
    }
}

/// Hover updates the row's appearance without rebuilding its input modifiers.
private struct BrowserSidebarTabRowAppearance: ViewModifier {
    let configuration: BrowserSidebarTabRowConfiguration
    @Binding var isHovering: Bool
    @Environment(\.sidebarLayerDepth) private var depth

    func body(content: Content) -> some View {
        content
            .background {
                BrowserTabStatusSurfaces(
                    tab: BrowserTabStatusSource(
                        tabID: configuration.tab.id, context: configuration.context,
                        canAct: { configuration.isCurrentAndUnlocked }),
                    style: BrowserTabStatusSurfaceStyle(
                        accent: accent, cornerRadius: BrowserSidebarMetrics.layerCornerRadius(depth: depth),
                        barOpacity: CrestOpacity.statusSurface)
                )
            }
            .modifier(
                BrowserTabAppearanceSurface(
                    appearance: BrowserDeviceAppearanceStore.shared.tabs,
                    accent: accent,
                    isPinned: false,
                    isSelected: configuration.isSelected,
                    isHovering: isHovering
                        || (!configuration.isSplitGroupMember
                            && BrowserSidebarSelection.showsSelected(
                                .tab(configuration.tab.id), in: configuration.context))
                )
            )
    }

    private var accent: Color {
        (BrowserDeviceAppearanceStore.shared.tabs.color ?? branding?.primaryColor ?? .indigo).color
    }

    private var branding: SpaceBranding? {
        configuration.spacePresentation?.branding
            ?? configuration.context.space.settings.look
    }
}
