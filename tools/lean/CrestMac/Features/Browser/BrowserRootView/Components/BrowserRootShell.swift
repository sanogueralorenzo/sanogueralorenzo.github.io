import SwiftUI

struct BrowserRootShell: View, BrowserChromeAnimating {
    let model: BrowserRootModel
    let spaceSettingsPresentation: BrowserSpaceSettingsPresentationState
    let shortcuts: BrowserShortcutStore?
    let commandSurfaceNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var downloadFeedback = BrowserMacDownloadFeedbackState()
    @State private var spacePagerPresentation = SpacePagerPresentation()

    /// The shell places the sidebar; the page frames under it read the rest.
    private var sidebarOnRight: Bool { BrowserChromeAppearance().sidebarOnRight }
    private var sidebarEdge: HorizontalEdge {
        BrowserChromeAppearance.sidebarEdge(onRight: sidebarOnRight, in: layoutDirection)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            BrowserRootFullscreenContent(
                pages: model.pages
            ) {
                standardContent
            }

            // Follow focus in the ordinary shell and fullscreen pages alike.
            BrowserWindowFocusBridge(isWindowFocused: model.isWindowFocusedBinding)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            // The window's chrome belongs to the window, not to the chrome a
            // fullscreen page hides: taking it down would restore the window's
            // style while AppKit is carrying it into fullscreen.
            BrowserNativeWindowControlsBridge(
                isVisible: model.sidebarPresentation.showsWindowControls
            )
            .frame(maxWidth: .infinity)
            .frame(height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            // A held Most Recent Tab shortcut shows the recent tabs over the
            // window, fullscreen page or not.
            BrowserRecentTabsLayer(chrome: model.chrome)

            // Notices show over a fullscreen page too, so one posted there
            // is never lost.
            BrowserNoticeLayer(chrome: model.chrome)
        }
        .overlayPreferenceValue(BrowserRootPageBoundsKey.self) { anchor in
            GeometryReader { proxy in
                let rect = anchor.map { proxy[$0] } ?? CGRect(origin: .zero, size: proxy.size)
                BrowserRootCommandPaletteLayer(
                    model: model,
                    shortcuts: shortcuts,
                    spaceSettingsPresentation: spaceSettingsPresentation,
                    commandSurfaceNamespace: commandSurfaceNamespace,
                    contentInsets: BrowserChromeAppearance.contentInsets(
                        for: rect, in: proxy.size, direction: layoutDirection
                    )
                )
            }
        }
        // One per-window host answers for every row and tile in this shell,
        // so the sidebar reads it from here rather than being handed a value
        // per tab through the tree between them.
        .environment(downloadFeedback)
        .environment(\.spacePagerPresentation, spacePagerPresentation)
        .environment(
            \.browserWebFocusRestorationGate,
            BrowserWebFocusRestorationGate(
                browserChromeOwnsFocus:
                    !model.isWindowFocused
                    || model.chrome.isCommandPalettePresented,
                pageChromeOwnsFocus: false
            )
        )
        .animation(chromeAnimation(CrestMotion.collection), value: sidebarOnRight)
        .animation(
            BrowserCommandSurfaceMorph.commandPaletteAnimation(reduceMotion: reduceMotion),
            value: model.isCommandPaletteShown
        )
        .animation(chromeAnimation(CrestMotion.floatingPane), value: model.isSidebarPresented)
        .onChange(of: model.isSidebarPresented) { model.sidebarPresentationChanged() }
        .onChange(of: model.chrome.utilityPresentation.isSidebarInteractionActive) { _, isActive in
            model.sidebarInteractionChanged(isActive, reduceMotion: reduceMotion)
        }
        .modifier(BrowserRootPermissionObserver(model: model))
        .transaction { transaction in
            if reduceMotion {
                transaction.disablesAnimations = true
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }

    private var standardContent: some View {
        ZStack(alignment: .leading) {
            BrowserRootBackdrop(
                space: model.browser.shownSpace,
                spaces: model.browser.availableSpaces
            )

            BrowserSidebarPageLayout(
                presentation: model.sidebarPresentation,
                width: model.sidebarWidth,
                edge: sidebarEdge
            ) {
                BrowserSpacePageSurface(
                    model: model,
                    tabPromotionNamespace: tabPromotionNamespace, shortcuts: shortcuts
                )
                .clipped()
            } sidebar: {
                sidebarSurface
            } controls: {
                shellControls
            }
            .allowsHitTesting(!model.chrome.isCommandPalettePresented)
            .accessibilityHidden(model.chrome.isCommandPalettePresented)

            BrowserMacDownloadFeedbackLayer(model: model, feedback: downloadFeedback)
                .zIndex(BrowserRootMetrics.utilityFanZIndex + 1)

            BrowserRootDragPreviewLayer(
                model: model,
                reduceMotion: reduceMotion
            )
        }
    }

    private var sidebarSurface: some View {
        BrowserRootSidebarSurfaceLayer(
            presentation: model.sidebarPresentation,
            width: model.sidebarWidth,
            edge: sidebarEdge,
            space: model.browser.shownSpace,
            reduceTransparency: reduceTransparency,
            spaces: model.browser.availableSpaces,
            isRevealedByPointer: model.isSidebarRevealedByPointer,
            hoverChanged: { model.sidebarSurfaceHoverChanged($0, reduceMotion: reduceMotion) }
        ) {
            BrowserRootSidebarContent(
                model: model,
                spaceSettingsPresentation: spaceSettingsPresentation,
                commandSurfaceNamespace: commandSurfaceNamespace,
                tabPromotionNamespace: tabPromotionNamespace
            )
        }
        .background {
            BrowserSidebarPointerNavigation(
                isSidebarVisible:
                    model.sidebarPresentation.showsSidebar
                    && !model.chrome.isCommandPalettePresented,
                perform: model.handleAuxiliaryMouseAction,
                navigationTargets: { [pages = model.pages] in pages.livePages },
                activeTarget: { [pages = model.pages] in pages.activePage }
            )
        }
    }

    private var shellControls: some View {
        BrowserRootShellControls(
            model: model
        )
        .zIndex(BrowserRootMetrics.floatingSidebarZIndex + 1)
    }
}

/// Tab selection is observed here so the ordinary shell's inputs stay stable
/// when only the page occupying it changes.
///
/// Page fullscreen leaves browser chrome outside the page surface.
private struct BrowserRootFullscreenContent<Content: View>: View {
    let pages: BrowserPagePool
    @ViewBuilder let content: Content

    var body: some View {
        if let page = pages.activePage, page.isContentFullscreen {
            ZStack(alignment: .leading) {
                BrowserPlatformWebView(
                    page: page,
                    isPageActive: true,
                    focusRestorationGate: .suppressed
                )
                .environment(\.browserPagePresentationWindowID, pages.windowID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
            }
            .ignoresSafeArea()
        } else {
            content
        }
    }
}

/// Permission prompts are anchored in the sidebar and must remain reachable.
private struct BrowserRootPermissionObserver: ViewModifier {
    let model: BrowserRootModel

    func body(content: Content) -> some View {
        content.onChange(of: model.pages.activePage?.sitePermissionRequests.current?.id) {
            if model.pages.activePage?.sitePermissionRequests.current != nil {
                model.chrome.showSidebar()
            }
        }
    }
}
