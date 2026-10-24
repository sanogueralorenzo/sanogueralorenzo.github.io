import SwiftUI

/// Actual sidebar components, with all actions contained in a memory-only Space.
///
/// The sample Space carries one of everything the appearance settings act on:
/// pins with site colors, a folder of saved tabs, a loose saved tab, loose open
/// tabs, and a Split View group. Rows select and hover so the choices show, and
/// nothing else — the sidebar here is for looking at, so it declines to be
/// rearranged or organized.
struct BrowserSidebarCustomizationPreview: View {
    var space: BrowserSpaceAppearance? = nil
    var showsPins = true
    var showsCurrentTabs = true
    var followsHighlightPreference = true
    /// Whether the preview draws the Space's atmosphere behind itself. The
    /// window crop already stands on that atmosphere, so it asks for the
    /// sidebar's contents alone.
    var showsBackground = true
    @Environment(\.browserInteractionCapabilities) private var hostCapabilities
    @Environment(\.colorScheme) private var colorScheme
    @State private var sample = BrowserAppearancePreviewState()

    private var capabilities: BrowserInteractionCapabilities {
        var value = hostCapabilities
        value.pairsRowWithPromotedSurface = false
        value.supportsOrganization = false
        return value
    }

    var body: some View {
        let context = sample.listContext(capabilities: capabilities)
        let branding = context.map(\.space.settings.look) ?? sample.fallbackBranding
        VStack(spacing: 8) {
            if let context {
                if showsPins {
                    let space = context.space
                    PinnedTabGrid(
                        tabs: space.sidebar.section(.pinned).rows.compactMap { space.tabs.model($0.id) },
                        favicons: context.favicons, assignment: context.assignment, window: context.window,
                        select: { sample.browser.selectTab($0.tabID) }, context: context,
                        siteThemeAccent: sample.siteThemeAccent, capabilities: capabilities
                    )
                    .padding(.horizontal, 8)
                }
                BrowserSavedTabsDropSection(context: context)
                if showsCurrentTabs {
                    BrowserCurrentTabsDropSection(context: context, openNewTab: {})
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: BrowserChromeLayout.sidebarMaximumWidth)
        .background { background(for: branding) }
        .clipShape(.rect(cornerRadius: showsBackground ? 14 : 0))
        .environment(\.colorScheme, branding.colorScheme(over: colorScheme))
        .environment(\.sidebarSpacePresentation, context.map { presentation(of: $0) })
        .environment(\.browserInteractionCapabilities, capabilities)
        .environment(sample.sidebarInteraction)
        .environment(\.folderPreviewShowsHighlight, !followsHighlightPreference)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Interactive sidebar preview")
        .onChange(of: space, initial: true) { _, space in sample.applyTheme(space) }
    }

    private func presentation(of context: BrowserSidebarListContext) -> SidebarSpacePresentation {
        SidebarSpacePresentation(space: context.space, isUnlocked: true)
    }

    @ViewBuilder
    private func background(for branding: SpaceBranding) -> some View {
        if showsBackground {
            BrowserSpaceBannerBackground(branding: branding)
        }
    }
}

@MainActor
@Observable
private final class BrowserAppearancePreviewState {
    let sidebarInteraction: BrowserSidebarInteractionState
    let browser: BrowserStore
    let spaceAccess = BrowserSpaceAccessController()
    let downloads = BrowserDownloadCenter(
        permissionCenter: BrowserSitePermissionCenter())
    /// The color each sample site would hand its pin, keyed the way the shipping
    /// sidebar asks for it.
    private let siteAccents: [UUID: BrowserTabIconAccent]

    init() {
        let folder = FolderState.Seed(title: String(localized: "Example folder"), symbol: "book.closed")
        let reading = TabState.Seed(
            title: String(localized: "Reading list"), url: URL(string: "https://preview.invalid/reading"),
            symbol: "book.closed", placement: .saved, folderID: folder.id)
        let plans = TabState.Seed(
            title: String(localized: "Weekend plans"), url: URL(string: "https://preview.invalid/plans"),
            symbol: "sun.max", placement: .saved, folderID: folder.id)
        let recipes = TabState.Seed(
            title: String(localized: "Recipes"), url: URL(string: "https://preview.invalid/recipes"),
            symbol: "fork.knife", placement: .saved)
        let pinSources: [(String, String, BrowserTabIconAccent)] = [
            ("Calendar", "calendar", BrowserTabIconAccent(red: 0.93, green: 0.30, blue: 0.24)),
            ("Mail", "envelope.fill", BrowserTabIconAccent(red: 0.20, green: 0.52, blue: 0.96)),
            ("Music", "music.note", BrowserTabIconAccent(red: 0.98, green: 0.28, blue: 0.52)),
            ("Books", "book.fill", BrowserTabIconAccent(red: 0.96, green: 0.60, blue: 0.14)),
        ]
        let pins = pinSources.map { title, symbol, accent in
            TabState.Seed(
                title: title, url: URL(string: "https://preview.invalid/" + title.lowercased()), symbol: symbol,
                iconAccent: TabIconAccent(red: accent.red, green: accent.green, blue: accent.blue), placement: .pinned)
        }
        let notes = TabState.Seed(
            title: String(localized: "Meeting notes"), url: URL(string: "https://preview.invalid/notes"),
            symbol: "note.text", placement: .current)
        let tickets = TabState.Seed(
            title: String(localized: "Flight tickets"), url: URL(string: "https://preview.invalid/tickets"),
            symbol: "airplane", placement: .current)
        let split = SplitGroupState.Seed()
        let docs = TabState.Seed(
            title: String(localized: "Draft"), url: URL(string: "https://preview.invalid/draft"),
            symbol: "doc.text", placement: .current, splitGroupID: split.id)
        let research = TabState.Seed(
            title: String(localized: "Research"), url: URL(string: "https://preview.invalid/research"),
            symbol: "magnifyingglass", placement: .current, splitGroupID: split.id)
        let space = SpaceState.Seed(
            name: "Preview", symbol: "paintpalette", accent: .indigo, branding: SpaceAccent.indigo.house,
            folders: [folder], tabs: pins + [reading, plans, recipes, notes, tickets, docs, research],
            splitGroups: [split])
        siteAccents = Dictionary(uniqueKeysWithValues: zip(pins.map(\.id), pinSources.map(\.2)))
        browser = BrowserStore(
            seed: SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: notes.id],
            browsingMode: .privateBrowsing)
        sidebarInteraction = BrowserSidebarInteractionState.connected(to: browser)
    }

    /// The sample Space as the read model holds it, and what its rows act
    /// through, in this preview's own memory-only store.
    func listContext(capabilities: BrowserInteractionCapabilities) -> BrowserSidebarListContext? {
        guard let space = browser.workspaceModel?.spaces.models.first, let window = browser.windowModel else {
            return nil
        }
        return BrowserSidebarListContext(
            space: space, window: window, favicons: browser.core.state.favicons, browser: browser,
            spaceAccess: spaceAccess, pageAccess: pageAccess, tabActions: tabActions, capabilities: capabilities,
            select: { [browser] in browser.selectTab($0) })
    }

    /// The look before the sample Space reaches the read model.
    var fallbackBranding: SpaceBranding { SpaceHouse.winter.look }

    var assignment: BrowserSpaceRuntimeAssignment {
        guard let space = browser.workspaceModel?.spaces.models.first else {
            return BrowserSpaceRuntimeAssignment(spaceID: UUID(), profileID: UUID())
        }
        return BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: space.profileID)
    }

    /// Wears the look and first folder's color and icon of `source`, the Space
    /// being edited, by changing this preview's own memory-only Space.
    func applyTheme(_ source: BrowserSpaceAppearance?) {
        guard let source, let space = browser.workspaceModel?.spaces.models.first else { return }
        browser.updateSpaceBranding(source.branding, in: space.id)
        if let folder = source.leadingFolder, let sample = space.folders.models.first {
            browser.setFolderColor(sample.id, in: space.id, color: folder.displayColor)
            browser.setFolderSymbol(sample.id, in: space.id, symbol: folder.displaySymbol)
        }
    }

    var siteThemeAccent: @Sendable (BrowserTabRuntimeAssignment) -> BrowserTabIconAccent? {
        { [siteAccents] assignment in siteAccents[assignment.tabID] }
    }

    var pageAccess: BrowserSidebarPageAccess {
        BrowserSidebarPageAccess(
            containsResidentPage: { _ in true }, containsResidentPageMatching: { _ in true },
            siteThemeIconAccent: siteThemeAccent, residencyRevision: { 0 }, selectPages: {},
            deactivatePagePresentation: {},
            unloadPage: { _, _ in }, pullFavicon: { _, _ in nil }, downloadCenter: downloads)
    }

    var tabActions: BrowserSidebarTabActions {
        BrowserSidebarTabActions(
            assignment: assignment, browser: browser, reorderState: sidebarInteraction.sidebarReorderState,
            spaceAccess: spaceAccess,
            syncPagesAfterMutation: {}, pullFavicon: { _, _ in nil })
    }
}
