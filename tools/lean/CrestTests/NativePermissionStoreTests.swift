import Foundation
import SQLite3
import XCTest

@testable import Crest

@MainActor
final class NativePermissionStoreTests: XCTestCase {
    private let origin = SiteOrigin(scheme: "https", host: "meet.example", port: 443)
    private func seed() -> SessionState.Seed {
        SessionState.Seed(spaces: [
            SpaceState.Seed(name: "Work", tabs: []), SpaceState.Seed(name: "Personal", tabs: []),
        ])
    }
    private func decide(
        _ core: CrestCore, _ space: UUID, _ permission: SitePermission, _ answer: SitePermissionDecision
    ) throws {
        try core.send(
            DecideSitePermission(spaceID: space, origin: origin, permission: permission, detail: nil, decision: answer))
    }
    private func answer(_ core: CrestCore, _ space: UUID, _ permission: SitePermission) throws -> SitePermissionDecision
    {
        try core.query(SiteDecision(spaceID: space, origin: origin, permission: permission, detail: nil)).decision
    }
    private func sql(_ file: URL, _ sql: String) throws {
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(file.path, &connection, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        defer { sqlite3_close_v2(connection) }
        XCTAssertEqual(sqlite3_exec(connection, sql, nil, nil, nil), SQLITE_OK)
    }
    func testOnlyStoredOwnerPersistsAndBorrowedWindowsUseItsChoices() async throws {
        let harness = try BrowserStoredSessionHarness(seed: seed())
        let core = harness.core
        let space = try XCTUnwrap(harness.store.spaceModels.first)
        XCTAssertTrue(try XCTUnwrap(core.state.workspaces[harness.store.family.workspaceID]).keepsFile)
        let borrowed = try XCTUnwrap(
            harness.store.makeTemporaryWindowStore(in: BrowserSpaceRuntimeAssignment(space: space)))
        let seeded = BrowserStore(seed: seed(), core: core)
        let privateBrowser = BrowserStore(seed: seed(), browsingMode: .privateBrowsing, core: core)
        let seededID = try XCTUnwrap(seeded.spaceModels.first).id
        let privateID = try XCTUnwrap(privateBrowser.spaceModels.first).id
        let stranger = UUID()
        for target in [space.id, seededID, privateID, stranger] {
            try decide(core, target, .camera, .grantPersistently)
        }
        try decide(core, space.id, .microphone, .grantForSession)
        try decide(borrowed.core, space.id, .location, .denyPersistently)
        XCTAssertEqual(try answer(core, seededID, .camera), .grantPersistently)
        XCTAssertFalse(try XCTUnwrap(core.state.workspaces[seeded.family.workspaceID]).keepsFile)
        let rows = try PermissionSQLite(directory: harness.directory).read()
        XCTAssertEqual(Set(rows.map(\.spaceID)), [space.id])
        XCTAssertEqual(Set(rows.map(\.permission)), [.camera, .location])
        try core.send(
            SetSpaceIdentity(workspaceID: harness.store.family.workspaceID, spaceID: space.id, name: "Renamed"))
        let relaunched = try await harness.relaunch()
        XCTAssertEqual(try answer(relaunched.core, space.id, .camera), .grantPersistently)
        XCTAssertEqual(try answer(relaunched.core, space.id, .location), .denyPersistently)
        for target in [seededID, privateID, stranger] {
            XCTAssertEqual(try answer(relaunched.core, target, .camera), .ask)
        }
        XCTAssertEqual(try answer(relaunched.core, space.id, .microphone), .ask)
        XCTAssertEqual(
            try PermissionSQLite(directory: relaunched.directory).read(), rows,
            "Session saves must not overwrite the native permission table")
    }
    func testSessionOverridesExpireAndRecordResetDoesNotClearAnOverride() async throws {
        let harness = try BrowserStoredSessionHarness(seed: seed())
        let core = harness.core
        let space = try XCTUnwrap(harness.store.spaceModels.first).id
        try decide(core, space, .camera, .grantPersistently)
        let id = try XCTUnwrap(core.state.sitePermissions[space]?.first).id
        try decide(core, space, .camera, .denyForSession)
        XCTAssertEqual(try answer(core, space, .camera), .denyForSession)
        let restarted = try await harness.relaunch()
        XCTAssertEqual(try answer(restarted.core, space, .camera), .grantPersistently)
        try core.send(ResetSitePermission(recordID: id))
        XCTAssertEqual(try answer(core, space, .camera), .denyForSession)
        XCTAssertNil(core.state.sitePermissions[space])
        try core.send(ResetSpacePermissions(spaceID: space))
        XCTAssertEqual(try answer(core, space, .camera), .ask)
        XCTAssertTrue(try PermissionSQLite(directory: harness.directory).read().isEmpty)
    }
    func testResetNotifiesSynchronouslyEvenWithNoSavedRowsAndUnknownRecordDoesNothing() throws {
        let core = CrestCore()
        let space = UUID()
        let owner = NSObject()
        var changes: [SitePermissionsChanged] = []
        core.followSitePermissions(owner) { changes.append($0) }
        try core.send(ResetSitePermission(recordID: UUID()))
        XCTAssertTrue(changes.isEmpty)
        try core.send(ResetSpacePermissions(spaceID: space))
        try core.send(ResetSpacePermissions(spaceID: space))
        XCTAssertEqual(changes.count, 2)
        XCTAssertTrue(
            changes.allSatisfy {
                $0.spaceID == space && $0.records.isEmpty
                    && $0.touched == [
                        SitePermissionScope(origin: nil, permission: nil, detail: nil, revokesAuthorization: true)
                    ]
            })
        let revision = core.state.sitePermissionRevision
        try decide(core, space, .camera, .grantForSession)
        XCTAssertEqual(core.state.sitePermissionRevision, revision + 1)
        XCTAssertEqual(changes.last?.touched.first?.revokesAuthorization, false)
        try decide(core, space, .camera, .ask)
        XCTAssertEqual(changes.last?.touched.first?.revokesAuthorization, true)
    }
    func testDefaultsAreAdoptedOnceAndKeepIdentityOrderAndExactDoubleBits() async throws {
        let harness = try BrowserStoredSessionHarness(seed: seed())
        let space = try XCTUnwrap(harness.store.spaceModels.first).id
        let id = UUID()
        let orphan = UUID()
        let time = 808529885.001641
        let entry: [String: Any] = [
            "id": id.uuidString, "spaceID": ["rawValue": space.uuidString],
            "origin": ["scheme": "HTTPS", "host": "Meet.Example", "port": 443], "permission": "camera",
            "decision": "grantPersistently", "modifiedAt": time,
        ]
        var old = entry
        old["spaceID"] = orphan.uuidString
        old["id"] = UUID().uuidString
        var session = entry
        session["permission"] = "microphone"
        session["decision"] = "denyForSession"
        let data = try JSONSerialization.data(withJSONObject: [entry, 7, old, session, entry])
        try harness.core.send(AdoptSitePermissions(records: data))
        let rows = try PermissionSQLite(directory: harness.directory).read()
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first?.id, id)
        XCTAssertEqual(rows.first?.modifiedAt.bitPattern, time.bitPattern)
        XCTAssertEqual(harness.core.state.sitePermissions[space]?.first?.siteName, "https://meet.example")
        try harness.core.send(AdoptSitePermissions(records: Data("[]".utf8)))
        XCTAssertEqual(try PermissionSQLite(directory: harness.directory).read(), rows)
        let restarted = try await harness.relaunch()
        XCTAssertEqual(try answer(restarted.core, space, .camera), .grantPersistently)
        try restarted.core.send(AdoptSitePermissions(records: data))
        XCTAssertEqual(try PermissionSQLite(directory: restarted.directory).read(), rows)
    }
    func testFailedWriteRollsBackRowsAndDoesNotPublishAnUnsavedChoice() throws {
        let harness = try BrowserStoredSessionHarness(seed: seed())
        let core = harness.core
        let space = try XCTUnwrap(harness.store.spaceModels.first).id
        try decide(core, space, .camera, .grantPersistently)
        let rows = try PermissionSQLite(directory: harness.directory).read()
        let revision = core.state.sitePermissionRevision
        try sql(
            harness.url,
            "CREATE TRIGGER fail_permission BEFORE INSERT ON device_site_permission BEGIN SELECT RAISE(ABORT,'test'); END"
        )
        XCTAssertThrowsError(try decide(core, space, .location, .grantPersistently))
        XCTAssertEqual(core.state.sitePermissionRevision, revision)
        XCTAssertEqual(try answer(core, space, .location), .ask)
        XCTAssertEqual(try PermissionSQLite(directory: harness.directory).read(), rows)
        try sql(harness.url, "DROP TRIGGER fail_permission")
        try decide(core, space, .location, .grantPersistently)
        XCTAssertEqual(try answer(core, space, .location), .grantPersistently)
    }
    func testNotificationEligibilityKeepsSecurePrivateAndProfileOwnershipRules() throws {
        let core = CrestCore()
        let browser = BrowserStore(seed: seed(), core: core)
        let space = try XCTUnwrap(browser.spaceModels.first)
        let borrowed = try XCTUnwrap(browser.makeTemporaryWindowStore(in: BrowserSpaceRuntimeAssignment(space: space)))
        XCTAssertEqual(borrowed.spaceModels.first?.id, space.id)
        let privateBrowser = BrowserStore(seed: seed(), browsingMode: .privateBrowsing, core: core)
        let privateSpace = try XCTUnwrap(privateBrowser.spaceModels.first)
        let insecure = SiteOrigin(scheme: "http", host: "meet.example", port: 80)
        let loopback = SiteOrigin(scheme: "http", host: "localhost", port: 80)
        for target in [space.id, privateSpace.id] {
            try decide(core, target, .notifications, .grantForSession)
            for origin in [insecure, loopback] {
                try core.send(
                    DecideSitePermission(
                        spaceID: target, origin: origin, permission: .notifications, detail: nil,
                        decision: .grantForSession))
            }
        }
        XCTAssertTrue(try core.query(NotificationDisplayCheck(spaceID: space.id, origin: origin)).shows)
        XCTAssertTrue(try core.query(NotificationDisplayCheck(spaceID: space.id, origin: loopback)).shows)
        XCTAssertFalse(try core.query(NotificationDisplayCheck(spaceID: space.id, origin: insecure)).shows)
        XCTAssertFalse(try core.query(NotificationDisplayCheck(spaceID: privateSpace.id, origin: origin)).shows)
        XCTAssertTrue(
            try core.query(
                ProfileNotificationDisplayCheck(profileID: space.profileID, origin: origin, source: .serviceWorker)
            ).shows)
        XCTAssertFalse(
            try core.query(
                ProfileNotificationDisplayCheck(
                    profileID: privateSpace.profileID, origin: origin, source: .serviceWorker)
            ).shows)
        XCTAssertFalse(
            try core.query(ProfileNotificationDisplayCheck(profileID: UUID(), origin: origin, source: .serviceWorker))
                .shows)
        let ext = SiteOrigin(scheme: "chrome-extension", host: "extension-id", port: 0)
        XCTAssertTrue(
            try core.query(ProfileNotificationDisplayCheck(profileID: space.profileID, origin: ext, source: .extension))
                .shows)
        XCTAssertFalse(
            try core.query(
                ProfileNotificationDisplayCheck(profileID: space.profileID, origin: origin, source: .extension)
            ).shows)
        let alias = BrowserStore(
            seed: SessionState.Seed(spaces: [SpaceState.Seed(profileID: space.profileID, name: "Other", tabs: [])]),
            core: core)
        XCTAssertFalse(alias.spaceModels.isEmpty)
        XCTAssertFalse(
            try core.query(
                ProfileNotificationDisplayCheck(profileID: space.profileID, origin: origin, source: .serviceWorker)
            ).shows)
    }
    func testMalformedDefaultsDoNotReplaceReadableChoices() throws {
        let base: [String: Any] = [
            "id": UUID().uuidString, "spaceID": UUID().uuidString,
            "origin": ["scheme": "https", "host": "meet.example", "port": 443], "permission": "camera",
            "decision": "grantPersistently", "modifiedAt": 1,
        ]
        XCTAssertEqual(PermissionDocument.read(try JSONSerialization.data(withJSONObject: [base, "bad"])).count, 1)
        XCTAssertTrue(PermissionDocument.read(Data("[".utf8)).isEmpty)
        var invalid = base
        invalid["detail"] = 7
        XCTAssertTrue(PermissionDocument.read(try JSONSerialization.data(withJSONObject: [invalid])).isEmpty)
        var nested: Any = 0
        for _ in 0..<9 { nested = [nested] }
        XCTAssertTrue(PermissionDocument.read(try JSONSerialization.data(withJSONObject: [base, nested])).isEmpty)
    }
}
