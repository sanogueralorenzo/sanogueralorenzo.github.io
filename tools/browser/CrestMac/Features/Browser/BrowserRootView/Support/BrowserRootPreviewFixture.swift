import Foundation

// MARK: - Types

enum BrowserRootPreviewState: Equatable {
    case docked
    case collapsed
    case commandPalette
}

enum BrowserRootPreviewFixture {
    static let spaceID = uuid(0x21)
    static let startTabID = uuid(0x41)
    static let space = SpaceState.Seed(
        id: spaceID,
        profileID: uuid(0x11),
        name: "Research",
        symbol: "books.vertical.fill",
        accent: .indigo,
        tabs: [
            TabState.Seed(
                id: uuid(0x42),
                title: "Apple Developer",
                url: URL(fileURLWithPath: "/preview/apple-developer"),
                symbol: "apple.logo",
                placement: .pinned,
                lastActivatedAt: Date(timeIntervalSince1970: 0)
            ),
            TabState.Seed(
                id: uuid(0x43),
                title: "WebKit Notes",
                url: URL(fileURLWithPath: "/preview/webkit-notes"),
                symbol: "safari.fill",
                placement: .current,
                lastActivatedAt: Date(timeIntervalSince1970: 0)
            ),
            TabState.Seed.startPage(
                id: startTabID,
                lastActivatedAt: Date(timeIntervalSince1970: 0)
            ),
        ]
    )

    static let splitGroupID = uuid(0x61)

    /// Two grouped current tabs, for previewing the split content area. Kept
    /// beside the fixture Space rather than inside it so every existing preview
    /// keeps rendering the single-page path it was written for.
    static let splitMembers: [TabState.Seed] = [
        TabState.Seed(
            id: uuid(0x62),
            title: "WebKit Notes",
            url: URL(fileURLWithPath: "/preview/webkit-notes"),
            symbol: "safari.fill",
            placement: .current,
            splitGroupID: splitGroupID,
            lastActivatedAt: Date(timeIntervalSince1970: 0)
        ),
        TabState.Seed(
            id: uuid(0x63),
            title: "Layout Research",
            url: URL(fileURLWithPath: "/preview/layout-research"),
            symbol: "ruler.fill",
            placement: .current,
            splitGroupID: splitGroupID,
            lastActivatedAt: Date(timeIntervalSince1970: 0)
        ),
    ]

    @MainActor
    static func makeBrowser() -> BrowserStore {
        BrowserStore(
            seed: SessionState.Seed(spaces: [space])
        )
    }

    @MainActor
    static func makeChrome(
        state: BrowserRootPreviewState = .docked
    ) -> BrowserChromeState {
        let chrome = BrowserChromeState(sidebarIsPresented: state != .collapsed)
        if state == .commandPalette {
            chrome.presentCommandPalette()
        }
        return chrome
    }

    @MainActor
    static func makeModel(
        state: BrowserRootPreviewState = .docked
    ) -> BrowserRootModel {
        let browser = makeBrowser()
        return BrowserRootModel(
            browser: browser,
            pages: BrowserPagePool(browser: browser),
            chrome: makeChrome(state: state),
            spaceAccess: BrowserSpaceAccessController(),
            windowState: makeWindowState(browser: browser),
            startupBehavior: .showStartPage,
            persistedSidebarWidth: BrowserChromeLayout.sidebarIdealWidth
        )
    }

    @MainActor
    static func makeWindowState(
        browser: BrowserStore
    ) -> BrowserWindowStateStore {
        let windowState = BrowserWindowStateStore(
            id: uuid(0x51),
            browser: browser,
            layouts: BrowserWindowLayouts(defaults: nil)
        )
        windowState.captureSidebar(
            width: Double(BrowserChromeLayout.sidebarIdealWidth),
            isPresented: true
        )
        return windowState
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x52,
                0x4F, 0x4F,
                0x54, 0x50,
                0x52, 0x45, 0x56, 0x49, 0x45, finalByte
            ))
    }
}
