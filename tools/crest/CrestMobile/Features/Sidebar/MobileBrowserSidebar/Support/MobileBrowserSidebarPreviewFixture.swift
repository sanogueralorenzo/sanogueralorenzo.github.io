import Foundation

@MainActor
struct MobileBrowserSidebarPreviewFixture {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController

    init() {
        let folder = FolderState.Seed(
            id: Self.uuid(0x21),
            title: "Reading",
            color: BrandColor.ocean,
            isCollapsed: false,
            collapseModifiedAt: Self.epoch
        )
        let pinnedTab = Self.tab(
            id: 0x31,
            title: "Crest Guide",
            path: "/CrestPreview/guide.html",
            emoji: "🧭",
            placement: .pinned
        )
        let savedTab = Self.tab(
            id: 0x32,
            title: "Design Notes",
            path: "/CrestPreview/design.html",
            emoji: "🎨",
            placement: .saved,
            folderID: folder.id
        )
        let unfiledSavedTab = Self.tab(
            id: 0x33,
            title: "SwiftUI Reference",
            path: "/CrestPreview/swiftui.html",
            emoji: "📚",
            placement: .saved
        )
        let currentTab = TabState.Seed.startPage(
            id: Self.uuid(0x34),
            placement: .current,
            lastActivatedAt: Self.epoch
        )
        let space = SpaceState.Seed(
            id: Self.uuid(0x11),
            profileID: Self.uuid(0x12),
            name: "Work",
            symbol: "briefcase.fill",
            accent: .indigo,
            branding: SpaceHouse.lion.look,
            folders: [folder],
            tabs: [pinnedTab, savedTab, unfiledSavedTab, currentTab],
            history: [
                HistoryEntryState(
                    id: Self.uuid(0x41),
                    url: URL(filePath: "/CrestPreview/history.html"),
                    title: "Crest History",
                    firstVisitedAt: Self.epoch,
                    lastVisitedAt: Self.epoch,
                    visitCount: 2
                )
            ]
        )
        let protectedSpace = SpaceState.Seed(
            id: Self.uuid(0x13),
            profileID: Self.uuid(0x14),
            name: "Personal",
            symbol: "lock.fill",
            accent: .orange,
            branding: SpaceHouse.winter.look,
            tabs: [],
            accessPolicy: .deviceOwnerAuthentication
        )
        let base = MobileBrowserPreviewFixture()

        browser = BrowserStore(
            seed: SessionState.Seed(spaces: [space, protectedSpace]),
            credentialVault: InMemoryCredentialVault(),
            browsingMode: .privateBrowsing
        )
        pages = base.pages
        spaceAccess = BrowserSpaceAccessController(
            authenticator: BrowserPreviewAuthenticator(result: false)
        )
    }

    private static let epoch = Date(timeIntervalSince1970: 0)

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x50, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
                0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, finalByte
            )
        )
    }

    private static func tab(
        id: UInt8,
        title: String,
        path: String,
        emoji: String,
        placement: TabPlacement,
        folderID: UUID? = nil
    ) -> TabState.Seed {
        TabState.Seed(
            id: uuid(id),
            title: title,
            url: URL(filePath: path),
            symbol: BrowserIconSymbol.symbol(forEmoji: emoji),
            placement: placement,
            folderID: folderID,
            lastActivatedAt: epoch,
            positionModifiedAt: epoch
        )
    }
}
