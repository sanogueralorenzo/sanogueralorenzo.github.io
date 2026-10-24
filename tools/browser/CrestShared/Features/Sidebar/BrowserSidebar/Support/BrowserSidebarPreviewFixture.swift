import Foundation

/// One Space with a little of everything, plus inert stand-ins for the ports the
/// sidebar reaches the rest of the app through.
///
/// Every identity and date is fixed, and the ports are closures that answer
/// without touching a page store, the filesystem, or the network — which is what
/// lets a preview of the sidebar render the same way twice.
enum BrowserSidebarPreviewFixture {
    static let folderID = uuid(0x31)
    static let spaceID = uuid(0x21)
    static let space = SpaceState.Seed(
        id: spaceID,
        profileID: uuid(0x11),
        name: "Studio",
        symbol: "paintpalette.fill",
        accent: .indigo,
        folders: [
            FolderState.Seed(
                id: folderID,
                title: "Design References",
                symbol: "folder.fill"
            )
        ],
        tabs: [
            tab(
                idByte: 0x41,
                title: "Apple Developer",
                path: "/preview/apple-developer",
                symbol: "apple.logo",
                placement: .pinned
            ),
            tab(
                idByte: 0x42,
                title: "SwiftUI Layout",
                path: "/preview/swiftui-layout",
                symbol: "rectangle.3.group.fill",
                placement: .saved,
                folderID: folderID
            ),
            tab(
                idByte: 0x43,
                title: "Crest Notes",
                path: "/preview/crest-notes",
                symbol: "note.text",
                placement: .current
            ),
            TabState.Seed.startPage(
                id: uuid(0x44),
                lastActivatedAt: Date(timeIntervalSince1970: 0)
            ),
        ]
    )

    @MainActor
    static func makeBrowser() -> BrowserStore {
        BrowserStore(
            seed: SessionState.Seed(spaces: [space]),
            browsingMode: .privateBrowsing
        )
    }

    @MainActor
    static func makeSpaceAccess() -> BrowserSpaceAccessController {
        BrowserSpaceAccessController(
            authenticator: BrowserPreviewAuthenticator(result: true)
        )
    }

    @MainActor
    static func makeUtilityPresentation(
        surface: BrowserUtilitySurface? = nil
    ) -> BrowserUtilityPresentationState {
        let presentation = BrowserUtilityPresentationState()
        if let surface {
            presentation.present(surface)
        }
        return presentation
    }

    /// A page seam that reports no resident pages and refuses every command.
    ///
    /// The closure port makes this trivial: there is no page store to stand up,
    /// so a preview of the sidebar draws the unloaded state of every row without
    /// a WebKit host anywhere in the picture.
    @MainActor
    static func makePageAccess(
        downloadCenter: BrowserDownloadCenter = BrowserDownloadCenter()
    ) -> BrowserSidebarPageAccess {
        BrowserSidebarPageAccess(
            containsResidentPage: { _ in false },
            containsResidentPageMatching: { _ in false },
            siteThemeIconAccent: { _ in nil },
            residencyRevision: { 0 },
            selectPages: {},
            deactivatePagePresentation: {},
            unloadPage: { _, _ in },
            pullFavicon: { _, _ in nil },
            downloadCenter: downloadCenter
        )
    }

    @MainActor
    static func makeUtilityCoordinator(
        browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController,
        downloadCenter: BrowserDownloadCenter = BrowserDownloadCenter()
    ) -> BrowserSidebarUtilityCoordinator {
        BrowserSidebarUtilityCoordinator(
            browser: browser,
            downloadCenter: downloadCenter,
            spaceAccess: spaceAccess,
            platformActions: BrowserSidebarUtilityPlatformActions(
                downloadDestinations: [],
                openHistoryEntry: { _, _ in },
                selectRestoredTab: { _ in },
                openFinishedDownload: { _, _ in },
                cancelDownload: { _ in },
                clearDownload: { _ in }
            )
        )
    }

    @MainActor
    static func makeChromeActions() -> BrowserSidebarChromeActions {
        BrowserSidebarChromeActions(
            presentSpaceSettings: { _ in },
            presentHistory: {},
            presentPasswords: {},
            presentArchive: {},
            presentDownloads: {},
            createSpace: {}
        )
    }

    private static func tab(
        idByte: UInt8,
        title: String,
        path: String,
        symbol: String,
        placement: TabPlacement,
        folderID: UUID? = nil
    ) -> TabState.Seed {
        TabState.Seed(
            id: uuid(idByte),
            title: title,
            url: URL(fileURLWithPath: path),
            symbol: symbol,
            placement: placement,
            folderID: folderID,
            lastActivatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x53,
                0x49, 0x44,
                0x45, 0x42,
                0x41, 0x52, 0x50, 0x52, 0x45, finalByte
            ))
    }
}
