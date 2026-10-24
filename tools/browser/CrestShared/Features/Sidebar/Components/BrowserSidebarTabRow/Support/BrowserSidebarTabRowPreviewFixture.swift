#if DEBUG
    import Foundation

    /// A tab for the previews of the setup and import rows, which draw tabs
    /// no window shows, as the core resolves it.
    @MainActor
    enum BrowserSidebarTabRowPreviewFixture {
        // MARK: - Static Variables

        static let profileID = uuid(0x72)
        static let tabID = uuid(0x73)
        static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        // MARK: - Actions - Fixtures

        static func tab(placement: TabPlacement = .current) -> TabStateModel {
            let tab = TabState.Seed(
                id: tabID, title: "Example", url: URL(fileURLWithPath: "/preview/example"), placement: placement,
                lastActivatedAt: fixedDate)
            return SpaceModel.detached(SpaceState.Seed(profileID: profileID, name: "Example", tabs: [tab])).tabs
                .models[0]
        }

        private static func uuid(_ suffix: UInt8) -> UUID {
            UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, suffix))
        }
    }
#endif
