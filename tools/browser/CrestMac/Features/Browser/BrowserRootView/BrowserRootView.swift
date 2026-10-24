import SwiftUI

struct BrowserRootView: View {
    private let transientBrowsing: BrowserTransientBrowsingCoordinator
    private let spaceSettingsPresentation: BrowserSpaceSettingsPresentationState
    private let shortcuts: BrowserShortcutStore?
    private let persistSidebarWidth: (Double) -> Void

    @Environment(\.browserChromeAppearance) private var appearance
    @State private var model: BrowserRootModel
    @State private var storedSidebarWidth: Double
    @Namespace private var commandSurfaceNamespace
    @Namespace private var tabPromotionNamespace

    init(
        browser: BrowserStore,
        pages: BrowserPagePool,
        chrome: BrowserChromeState,
        transientBrowsing: BrowserTransientBrowsingCoordinator,
        spaceAccess: BrowserSpaceAccessController = BrowserSpaceAccessController(),
        windowState: BrowserWindowStateStore? = nil,
        spaceSettingsPresentation: BrowserSpaceSettingsPresentationState =
            BrowserSpaceSettingsPresentationState(),
        startupBehavior: StartupBehavior = .showStartPage,
        shortcuts: BrowserShortcutStore? = nil,
        initialSidebarWidth: Double? = nil,
        persistSidebarWidth: @escaping (Double) -> Void =
            BrowserRootSidebarWidthPersistence.write
    ) {
        self.transientBrowsing = transientBrowsing
        self.spaceSettingsPresentation = spaceSettingsPresentation
        self.shortcuts = shortcuts
        self.persistSidebarWidth = persistSidebarWidth
        let fallbackWidth =
            initialSidebarWidth.map { CGFloat($0) }
            ?? BrowserRootSidebarWidthPersistence.read()
        let resolvedWidth = windowState?.sidebarWidth ?? Double(fallbackWidth)
        _storedSidebarWidth = State(initialValue: resolvedWidth)
        _model = State(
            initialValue: BrowserRootModel(
                browser: browser,
                pages: pages,
                chrome: chrome,
                spaceAccess: spaceAccess,
                windowState: windowState,
                startupBehavior: startupBehavior,
                persistedSidebarWidth:
                    CGFloat(resolvedWidth)
            )
        )
    }

    var body: some View {
        BrowserRootShell(
            model: model,
            transientBrowsing: transientBrowsing,
            spaceSettingsPresentation: spaceSettingsPresentation,
            shortcuts: shortcuts,
            storedSidebarWidth: $storedSidebarWidth,
            appearance: appearance,
            commandSurfaceNamespace: commandSurfaceNamespace,
            tabPromotionNamespace: tabPromotionNamespace
        )
        .modifier(
            BrowserRootLifecycleModifier(
                model: model,
                storedSidebarWidth: $storedSidebarWidth,
                persistSidebarWidth: persistSidebarWidth
            )
        )
        .environment(model.sidebarInteraction)
        // Extension controls anywhere in the window open the panel into this
        // window's own row, so they read the host rather than being handed it.
        .environment(model.extensionSidePanel)
        // `chrome.sidePanel.open()` and an action click that opens a panel
        // reach the engine host, which has a page but no view context, so this
        // window publishes the host that owns its row.
        .modifier(BrowserExtensionSidePanelRegistration(host: model.extensionSidePanel, pages: model.pages))
        .modifier(BrowserPopupWindowPresentation(pages: model.pages))
        .modifier(BrowserRootWindowTitle(model: model))
    }
}

/// Page titles update the window without rebuilding its browser shell.
private struct BrowserRootWindowTitle: ViewModifier {
    let model: BrowserRootModel

    func body(content: Content) -> some View {
        content.navigationTitle(Text(verbatim: model.windowTitle))
    }
}

#Preview("Browser Root — Docked") {
    let browser = BrowserRootPreviewFixture.makeBrowser()
    BrowserRootView(
        browser: browser,
        pages: BrowserPagePool(browser: browser),
        chrome: BrowserRootPreviewFixture.makeChrome(state: .docked),
        transientBrowsing: BrowserTransientBrowsingCoordinator(),
        windowState: BrowserRootPreviewFixture.makeWindowState(
            browser: browser
        ),
        initialSidebarWidth: Double(BrowserChromeLayout.sidebarIdealWidth),
        persistSidebarWidth: { _ in }
    )
    .frame(width: 1_120, height: 720)
}

#Preview("Browser Root — Collapsed") {
    let browser = BrowserRootPreviewFixture.makeBrowser()
    BrowserRootView(
        browser: browser,
        pages: BrowserPagePool(browser: browser),
        chrome: BrowserRootPreviewFixture.makeChrome(state: .collapsed),
        transientBrowsing: BrowserTransientBrowsingCoordinator(),
        windowState: BrowserRootPreviewFixture.makeWindowState(
            browser: browser
        ),
        initialSidebarWidth: Double(BrowserChromeLayout.sidebarIdealWidth),
        persistSidebarWidth: { _ in }
    )
    .frame(width: 1_120, height: 720)
}

#Preview("Browser Root — Command Palette") {
    let browser = BrowserRootPreviewFixture.makeBrowser()
    BrowserRootView(
        browser: browser,
        pages: BrowserPagePool(browser: browser),
        chrome: BrowserRootPreviewFixture.makeChrome(state: .commandPalette),
        transientBrowsing: BrowserTransientBrowsingCoordinator(),
        windowState: BrowserRootPreviewFixture.makeWindowState(
            browser: browser
        ),
        initialSidebarWidth: Double(BrowserChromeLayout.sidebarIdealWidth),
        persistSidebarWidth: { _ in }
    )
    .frame(width: 1_120, height: 720)
}
