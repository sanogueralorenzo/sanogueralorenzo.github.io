import XCTest

@testable import Crest

@MainActor
final class WebKitEngineBindingErasureTests: XCTestCase {
    /// WebKit erases a profile's stores when the core asks, though no page of
    /// the profile opened this run, and the deletion ends only as it answers.
    func testAnIdleWebKitEngineErasesAProfileItNeverOpenedAndReportsWhetherItCould() async {
        let stores = ErasingProfileStores()
        let core = CrestCore.hostingPages(profileStores: stores)
        let profileID = UUID()

        let deleted = await core.deleteData(
            DeleteProfileData(requestID: UUID(), profileID: profileID, ephemeral: false))
        XCTAssertTrue(deleted)
        XCTAssertEqual(stores.erased.map(\.id), [profileID])
        XCTAssertEqual(stores.erased.map(\.ephemeral), [false])

        stores.fails = true
        let failed = await core.deleteData(DeleteProfileData(requestID: UUID(), profileID: profileID, ephemeral: false))
        XCTAssertFalse(failed)
    }
}

/// A profile's stores that record what WebKit's binding erases, or refuse.
@MainActor
private final class ErasingProfileStores: BrowserEngineProfileRemoving {
    private(set) var erased: [(id: UUID, ephemeral: Bool)] = []
    var fails = false

    func removeProfile(_ profile: BrowsingProfile, ephemeral: Bool) async throws {
        if fails { throw CancellationError() }
        erased.append((profile.id, ephemeral))
    }
}
