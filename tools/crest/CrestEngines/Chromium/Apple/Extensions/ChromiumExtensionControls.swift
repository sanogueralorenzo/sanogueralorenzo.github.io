import SwiftUI

struct BrowserPinnedExtensionStrip: View {
    let page: ChromiumNativePage?
    /// The Space whose row this is, in the read model.
    let space: SpaceModel
    let browser: BrowserStore
    private var store: ChromiumExtensionStore { ChromiumComposition.extensions }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(BrowserExtensionSidePanelHost.self) private var sidePanel: BrowserExtensionSidePanelHost?

    var body: some View {
        // The row is the Space's, not the page's: a Space showing its Start Page
        // still has the extensions the user pinned to it.
        let actions = store.pinnedActions(for: space.identity, page: page)
        // The container is always in the view tree, empty or not. SwiftUI does
        // not run `task` on a conditional that resolves to nothing, and the
        // Space's engine profile is what the row needs to have any action to
        // show: hanging the preparation off the populated row alone left a
        // Space that had never opened a page with a row that never filled.
        VStack(spacing: 0) {
            if !actions.isEmpty {
                BrowserPinnedExtensionStripContent(
                    actions: actions,
                    perform: run,
                    presentMenu: { action, anchor in
                        store.presentMenu(
                            action, space: space.identity, anchor: anchor,
                            isPrivate: page?.isPrivateBrowsing ?? false,
                            openSidePanel: page.flatMap {
                                BrowserExtensionSidePanelHost.opener(action, page: $0, host: sidePanel)
                            })
                    }
                )
                .padding(.top, BrowserSidebarMetrics.topSectionSpacing)
                // Pinned tabs below hold the same gap above themselves.
                .padding(.bottom, space.sidebar.section(.pinned).isEmpty ? BrowserSidebarMetrics.topSectionSpacing : 0)
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : SpacePagerSettlement.standardAnimation, value: actions.map(\.id))
        .task(id: PreparationKey(space: space.id, profile: space.profileID)) {
            await store.prepare(space.identity, in: browser)
        }
    }

    /// Preparation is per Space and per engine profile, and is idempotent: the
    /// store keeps the profile it loaded and answers a repeat immediately.
    private struct PreparationKey: Equatable {
        let space: UUID
        let profile: UUID
    }

    private func run(
        _ action: BrowserExtensionActionPresentation,
        anchor: BrowserExtensionPopupAnchor?
    ) {
        guard let page else {
            store.runPinned(action, space: space.identity, anchor: anchor)
            return
        }
        page.runExtension(action.id, anchor: anchor)
    }
}

struct ChromiumExtensionControls: View {
    let page: ChromiumNativePage
    /// The page's Space in the read model.
    let space: SpaceModel
    let url: URL?
    let dismiss: () -> Void
    private var store: ChromiumExtensionStore { ChromiumComposition.extensions }
    @Environment(BrowserExtensionSidePanelHost.self) private var sidePanel: BrowserExtensionSidePanelHost?

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            Divider()
            BrowserSiteExtensionsSection(
                actions: store.actions(for: page),
                manageExtensions: { afterDismiss { ChromiumComposition.openExtensionSettings() } },
                perform: { action, anchor in
                    let retained = anchor?.replacingSourceWindow(page.surface.window)
                    afterDismiss { page.runExtension(action.id, anchor: retained) }
                },
                togglePinned: { store.togglePin($0, space: space.identity) },
                // Site Controls stays open under the menu, as it does for the
                // pin button, and closes only for an item that leads elsewhere.
                presentMenu: { action, anchor in
                    store.presentMenu(
                        action, space: space.identity, anchor: anchor,
                        isPrivate: page.isPrivateBrowsing,
                        openSidePanel: BrowserExtensionSidePanelHost.opener(
                            action, page: page, host: sidePanel),
                        closeSource: dismiss)
                })
            if !page.isPrivateBrowsing, let id = ChromiumNativePage.webStoreExtensionID(url) {
                Button("Install Extension…", systemImage: "plus.app") {
                    afterDismiss { store.install(id, in: space.identity, anchor: page.surface) }
                }
            }
        }
    }
    private func afterDismiss(_ action: @escaping @MainActor () -> Void) {
        dismiss()
        Task { @MainActor in
            await Task.yield()
            action()
        }
    }
}
