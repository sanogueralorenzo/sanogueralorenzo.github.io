import Foundation

@MainActor
enum BrowserQuickWindowPreviewFixture {
    static let sourceSpace = makeSpace(
        idByte: 0x11,
        profileByte: 0x21,
        tabByte: 0x31,
        name: "Research",
        symbol: "books.vertical.fill",
        accent: .indigo
    )
    static let destinationSpace = makeSpace(
        idByte: 0x12,
        profileByte: 0x22,
        tabByte: 0x32,
        name: "Personal",
        symbol: "house.fill",
        accent: .orange
    )
    static let request = BrowserQuickWindowRequest.empty(
        id: uuid(0x41),
        spaceAssignment: BrowserSpaceRuntimeAssignment(spaceID: sourceSpace.id, profileID: sourceSpace.profileID)
    )

    static func makeBrowser() -> BrowserStore {
        BrowserStore(
            seed: SessionState.Seed(spaces: [sourceSpace, destinationSpace]),
            credentialVault: InMemoryCredentialVault(),
            browsingMode: .privateBrowsing
        )
    }

    static func makeModel() -> BrowserQuickWindowModel {
        BrowserQuickWindowModel(
            previewing: request,
            browser: makeBrowser(),
            spaceAccess: makeAccessController()
        )
    }

    static func makeAccessController() -> BrowserSpaceAccessController {
        BrowserSpaceAccessController(
            authenticator: BrowserPreviewAuthenticator(result: false)
        )
    }

    private static func makeSpace(
        idByte: UInt8,
        profileByte: UInt8,
        tabByte: UInt8,
        name: String,
        symbol: String,
        accent: SpaceAccent
    ) -> SpaceState.Seed {
        let tabID = uuid(tabByte)
        return SpaceState.Seed(
            id: uuid(idByte),
            profileID: uuid(profileByte),
            name: name,
            symbol: symbol,
            accent: accent,
            tabs: [
                TabState.Seed.startPage(
                    id: tabID,
                    lastActivatedAt: Date(timeIntervalSince1970: 0)
                )
            ]
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x51,
                0x55, 0x49,
                0x43, 0x4B,
                0x57, 0x49, 0x4E, 0x44, 0x4F, finalByte
            ))
    }
}
