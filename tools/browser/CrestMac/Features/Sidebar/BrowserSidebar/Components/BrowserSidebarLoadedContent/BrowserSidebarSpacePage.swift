import SwiftUI

struct BrowserSidebarSpacePage: View {
    @Environment(\.colorScheme) private var colorScheme
    private let assignment: BrowserSpaceRuntimeAssignment
    let isSelected: Bool
    let pages: BrowserPagePool
    let openNewTab: () -> Void
    let commandSurfaceNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID

    // Cache only this page's inputs, not the root context's complete Space
    // collection and unrelated sidebar actions. Re-initialization still
    // supplies fresh owners, bindings and callbacks on every root update.
    private let browser: BrowserStore
    private let spaceAccess: BrowserSpaceAccessController
    private let capabilities: BrowserInteractionCapabilities
    private let chromeActions: BrowserSidebarChromeActions
    private let utilityPresentation: BrowserUtilityPresentationState
    private let utilityActions: BrowserUtilityListActions
    private let utilitySearchText: Binding<String>
    private let utilityFilter: Binding<BrowserUtilityListFilter>
    private let downloadCenter: BrowserDownloadCenter
    private let dismissUtilityOnBlankSpace: () -> Void
    private let confirmClearHistory: (SpaceModel) -> Void

    init(
        space: SpaceModel,
        isSelected: Bool,
        context: BrowserSidebarContext,
        pages: BrowserPagePool,
        openNewTab: @escaping () -> Void,
        commandSurfaceNamespace: Namespace.ID,
        tabPromotionNamespace: Namespace.ID
    ) {
        assignment = BrowserSpaceRuntimeAssignment(space: space)
        self.isSelected = isSelected
        self.pages = pages
        self.openNewTab = openNewTab
        self.commandSurfaceNamespace = commandSurfaceNamespace
        self.tabPromotionNamespace = tabPromotionNamespace
        browser = context.browser
        spaceAccess = context.spaceAccess
        capabilities = context.capabilities
        chromeActions = context.chromeActions
        utilityPresentation = context.utilityPresentation
        utilityActions = context.utilityActions
        utilitySearchText = context.utilitySearchText
        utilityFilter = context.utilityFilter
        downloadCenter = context.pageAccess.downloadCenter
        dismissUtilityOnBlankSpace = context.dismissUtilityOnBlankSpace
        confirmClearHistory = context.confirmClearHistory
    }

    @ViewBuilder
    var body: some View {
        // AppKit retains this root between pager updates. Resolve its Space
        // here so tab removal and selection cannot lag behind live residency.
        if let space = browser.spaceModel(matching: assignment) {
            content(for: space)
        }
    }

    /// Authorization and selection are checked again when the field mounts, including after a pending Find.
    private func consumeSearchFocusRequest(_ request: Int, for surface: BrowserUtilitySurface) -> Bool {
        guard let space = browser.spaceModel(matching: assignment), browser.shownSpace?.id == space.id,
            !spaceAccess.isLocked(space)
        else { return false }
        return utilityPresentation.consumeSearchFocusRequest(request, for: surface)
    }

    private func content(for space: SpaceModel) -> some View {
        let isLocked = spaceAccess.isLocked(space)
        // These callbacks use the page and their action owners, independently
        // of the selected role that changes on the surrounding native host.
        let pageSpace = space
        let actions = chromeActions
        let confirmClear = confirmClearHistory
        return SpaceSidebarContent(
            space: space,
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess,
            capabilities: capabilities,
            openNewTab: openNewTab,
            showHistory: chromeActions.presentHistory,
            commandSurfaceNamespace: commandSurfaceNamespace,
            tabPromotionNamespace: tabPromotionNamespace,
            editSpace: { actions.presentSpaceSettings(BrowserSpaceRuntimeAssignment(space: pageSpace)) },
            createSpace: actions.createSpace,
            utilitySurface: utilityPresentation.surface,
            utilitySearchText: utilitySearchText,
            utilityFilter: utilityFilter,
            utilityDownloads: downloadCenter.items(
                for: space.profileID
            ),
            utilityActions: utilityActions,
            dismissUtilityOnBlankSpace: dismissUtilityOnBlankSpace,
            clearHistory: { confirmClear(pageSpace) },
            utilitySearchFocusRequest: utilityPresentation.searchFocusRequest,
            consumeUtilitySearchFocusRequest: consumeSearchFocusRequest
        )
        .environment(\.sidebarSpacePresentation, SidebarSpacePresentation(space: space, isUnlocked: !isLocked))
        .environment(\.sidebarSpaceIsSelected, isSelected)
        // Blur and redaction are drawing effects; rows still run their tasks.
        // This stops the ones that would otherwise disclose a locked Space's
        // hostnames to the network.
        .environment(\.browserSpaceContentIsLocked, isLocked)
        .onChange(of: isLocked) { _, locked in
            if locked, isSelected { browser.tabMultiSelection.clear() }
        }
        .environment(
            \.colorScheme,
            space.settings.look.shown.colorScheme(over: colorScheme)
        )
        .blur(
            radius: isLocked
                ? BrowserSidebarMetrics.lockedSpaceBlurRadius
                : 0
        )
        .redacted(reason: isLocked ? .placeholder : [])
        .allowsHitTesting(isSelected && !isLocked)
        // Retained offscreen pages must not participate when AppKit rebuilds
        // keyboard navigation for a newly focused Start Page command field.
        // An empty interaction set avoids adding a focus stop for the container.
        .focusable(isSelected && !isLocked, interactions: [])
        .accessibilityHidden(!isSelected || isLocked)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(space.settings.name) Space")
    }

}
