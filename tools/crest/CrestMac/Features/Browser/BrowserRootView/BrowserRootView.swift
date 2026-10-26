import SwiftUI

struct BrowserRootView: View {
    private let spaceSettingsPresentation: BrowserSpaceSettingsPresentationState
    private let shortcuts: BrowserShortcutStore?
    private let persistSidebarWidth: (Double) -> Void

    @State private var model: BrowserRootModel
    @State private var storedSidebarWidth: Double
    @Namespace private var commandSurfaceNamespace
    @Namespace private var tabPromotionNamespace

    init(
        browser: BrowserStore,
        pages: BrowserPagePool,
        chrome: BrowserChromeState,

        windowState: BrowserWindowStateStore? = nil,
        spaceSettingsPresentation: BrowserSpaceSettingsPresentationState =
            BrowserSpaceSettingsPresentationState(),
        shortcuts: BrowserShortcutStore? = nil,
        initialSidebarWidth: Double? = nil,
        persistSidebarWidth: @escaping (Double) -> Void =
            BrowserRootSidebarWidthPersistence.write
    ) {
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
                windowState: windowState,
                persistedSidebarWidth:
                    CGFloat(resolvedWidth)
            )
        )
    }

    var body: some View {
        BrowserRootShell(
            model: model,

            spaceSettingsPresentation: spaceSettingsPresentation,
            shortcuts: shortcuts,
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
        .environment(\.browserShortcutBindings, model.browser.core.state.shortcuts)
        .environment(model.sidebarInteraction)
        // Extension controls anywhere in the window open the panel into this
        // window's own row, so they read the host rather than being handed it.
        .environment(model.extensionSidePanel)
        // `chrome.sidePanel.open()` and an action click that opens a panel
        // reach the engine host, which has a page but no view context, so this
        // window publishes the host that owns its row.
        .modifier(BrowserExtensionSidePanelRegistration(host: model.extensionSidePanel, pages: model.pages))
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
        chrome: BrowserRootPreviewFixture.makeChrome(state: .expanded),

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

        windowState: BrowserRootPreviewFixture.makeWindowState(
            browser: browser
        ),
        initialSidebarWidth: Double(BrowserChromeLayout.sidebarIdealWidth),
        persistSidebarWidth: { _ in }
    )
    .frame(width: 1_120, height: 720)
}
