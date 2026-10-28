import Foundation

/// Which persistent WebKit website data store each profile opens in a launch.
extension BrowserLaunchEnvironment {
    // MARK: - Static Variables

    /// The namespace every named isolated launch derives its own from
    /// (04d9f602-9135-4933-88bf-bdb62c7d619d). It is frozen: a different value
    /// would leave every review's existing stores behind.
    private static let isolatedWebsiteDataStores = UUID(
        uuid: (
            0x04, 0xd9, 0xf6, 0x02, 0x91, 0x35, 0x49, 0x33,
            0x88, 0xbf, 0xbd, 0xb6, 0x2c, 0x7d, 0x61, 0x9d
        ))

    // MARK: - Actions - Website data

    /// The identifier of the persistent WebKit store `profileID` opens.
    ///
    /// Every launch except a named isolated one opens the profile's own store.
    /// A named isolated launch derives its store from its isolation ID and the
    /// profile ID. WebKit keeps identified stores per bundle, and a review that
    /// opens a copy of the installed session carries the installed profile IDs.
    /// Without this, a review signed as the installed app would share the
    /// person's cookies and site storage, and clearing site data or deleting a
    /// Space there would erase them. Relaunching with the same isolation ID
    /// finds the same stores again.
    func websiteDataStoreIdentifier(forProfileID profileID: UUID) -> UUID {
        guard requiresIsolation, let persistentIsolationID else { return profileID }
        let isolation = UUID(name: Data(persistentIsolationID.utf8), namespace: Self.isolatedWebsiteDataStores)
        return UUID(name: Data(profileID.uuidString.lowercased().utf8), namespace: isolation)
    }
}
