import SwiftUI

/// Owns shared Space selection, utility state, and clear-history confirmation.
/// Each platform supplies its layout through `BrowserSidebarContext`.
struct BrowserSidebar<Content: View>: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction
    let browser: BrowserStore
    let pageAccess: BrowserSidebarPageAccess
    let spaceAccess: BrowserSpaceAccessController

    /// What the hosting shell can do. Resolved by the host and handed down
    /// unchanged, so every row under this sidebar answers to one value.
    let capabilities: BrowserInteractionCapabilities

    let utilityCoordinator: BrowserSidebarUtilityCoordinator
    let utilityPresentation: BrowserUtilityPresentationState
    let chromeActions: BrowserSidebarChromeActions

    /// Whether this shell keeps the selected Space's page on screen beside the
    /// sidebar. Where it does, changing Space brings the new Space's page up;
    /// where the sidebar *is* the screen, changing Space takes the page down
    /// and nothing is waiting on the pager.
    let presentsSelectedSpacePage: Bool

    /// Called once the session has moved, with the Space that ended up
    /// selected, or `nil` when it is locked or gone. This is where a shell that
    /// owns the address field brings it back in step; a shell whose root model
    /// already observes the session does nothing.
    let spaceSelectionChanged: (SpaceModel?) -> Void

    @ViewBuilder let content: (BrowserSidebarContext) -> Content

    @State private var utilitySearchText = ""
    @State private var utilityFilter = BrowserUtilityListFilter.all
    @State private var clearHistoryConfirmation: BrowserSidebarClearHistoryConfirmation?

    init(
        browser: BrowserStore,
        pageAccess: BrowserSidebarPageAccess,
        spaceAccess: BrowserSpaceAccessController,
        capabilities: BrowserInteractionCapabilities,
        utilityCoordinator: BrowserSidebarUtilityCoordinator,
        utilityPresentation: BrowserUtilityPresentationState,
        chromeActions: BrowserSidebarChromeActions,
        presentsSelectedSpacePage: Bool = true,
        spaceSelectionChanged: @escaping (SpaceModel?) -> Void = { _ in },
        @ViewBuilder content: @escaping (BrowserSidebarContext) -> Content
    ) {
        self.browser = browser
        self.pageAccess = pageAccess
        self.spaceAccess = spaceAccess
        self.capabilities = capabilities
        self.utilityCoordinator = utilityCoordinator
        self.utilityPresentation = utilityPresentation
        self.chromeActions = chromeActions
        self.presentsSelectedSpacePage = presentsSelectedSpacePage
        self.spaceSelectionChanged = spaceSelectionChanged
        self.content = content
    }

    var body: some View {
        content(context)
            .environment(\.browserInteractionCapabilities, capabilities)
            .modifier(
                BrowserSidebarClearHistoryDialog(
                    browser: browser,
                    spaceAccess: spaceAccess,
                    confirmation: $clearHistoryConfirmation
                )
            )
            .onChange(of: utilityPresentation.surface) { previous, current in
                if previous != current {
                    utilitySearchText = ""
                    utilityFilter = .all
                }
                utilityCoordinator.acknowledgeDownloads(ifPresented: current)
            }
            .onChange(of: selectedDownloadIDs) {
                utilityCoordinator.acknowledgeDownloads(
                    ifPresented: utilityPresentation.surface
                )
            }
    }

    private var context: BrowserSidebarContext {
        BrowserSidebarContext(
            sidebarInteraction: sidebarInteraction,
            browser: browser,
            pageAccess: pageAccess,
            spaceAccess: spaceAccess,
            capabilities: capabilities,
            availableSpaces: browser.availableSpaces,
            utilityPresentation: utilityPresentation,
            utilityActions: utilityCoordinator.actions,
            utilitySearchText: $utilitySearchText,
            utilityFilter: $utilityFilter,
            chromeActions: chromeActions,
            selectSpace: selectSpace,
            confirmClearHistory: confirmClearHistory(for:),
            dismissUtilityOnBlankSpace: dismissUtilityOnBlankSpace,
            toggleUtilitySwitcher: toggleUtilitySwitcher
        )
    }

    private var selectedDownloadIDs: [UUID] {
        utilityCoordinator.selectedDownloads.map(\.id)
    }

    private var newUtilityDownloads: [DownloadState] {
        guard let profileID = browser.shownSpace?.profileID else { return [] }
        return pageAccess.downloadCenter.unacknowledgedItems(for: profileID)
    }

    private func dismissUtilityOnBlankSpace() {
        utilityPresentation.handleInteraction(.sidebarBlankSpace)
    }

    private func toggleUtilitySwitcher() {
        utilityPresentation.toggleSwitcher(
            hasNewDownloads: !newUtilityDownloads.isEmpty
        )
    }

    private func confirmClearHistory(for space: SpaceModel) {
        clearHistoryConfirmation =
            BrowserSidebarClearHistoryConfirmation(for: space, in: browser, accessController: spaceAccess)
    }

    /// Moves the session to a Space, then decides what the page layer does
    /// about it.
    ///
    /// A shell that has no page beside the sidebar takes the outgoing page down
    /// before the session moves, so nothing is briefly showing one Space's page
    /// under another Space's tabs.
    private func selectSpace(_ spaceID: UUID) {
        guard spaceID != browser.selectedSpaceID else { return }
        if !presentsSelectedSpacePage {
            pageAccess.deactivatePagePresentation()
        }
        browser.selectSpace(spaceID)
        guard let space = selectedUnlockedSpace else {
            pageAccess.deactivatePagePresentation()
            spaceSelectionChanged(nil)
            return
        }
        spaceSelectionChanged(space)
        if presentsSelectedSpacePage { pageAccess.selectPages() }
    }

    private var selectedUnlockedSpace: SpaceModel? {
        guard let space = browser.shownSpace, !spaceAccess.isLocked(space) else { return nil }
        return space
    }
}

#Preview("Browser Sidebar — Space Pager") {
    let browser = BrowserSidebarPreviewFixture.makeBrowser()
    let spaceAccess = BrowserSidebarPreviewFixture.makeSpaceAccess()
    BrowserSidebar(
        browser: browser,
        pageAccess: BrowserSidebarPreviewFixture.makePageAccess(),
        spaceAccess: spaceAccess,
        capabilities: BrowserInteractionCapabilities(),
        utilityCoordinator: BrowserSidebarPreviewFixture.makeUtilityCoordinator(
            browser: browser,
            spaceAccess: spaceAccess
        ),
        utilityPresentation:
            BrowserSidebarPreviewFixture.makeUtilityPresentation(),
        chromeActions: BrowserSidebarPreviewFixture.makeChromeActions()
    ) { context in
        BrowserSidebarSpacePager(context: context) { space, isSelected in
            VStack {
                Text(space.settings.name)
                    .font(.headline)
                Text("\(space.tabs.models.count) tabs")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isSelected ? 1 : 0.4)
        }
    }
    .environment(BrowserSidebarInteractionState.connected(to: browser))
    .frame(width: 280, height: 420)
}
