import Foundation
import XCTest

@testable import Crest

final class NativePermissionLedgerTests: XCTestCase {
    private let meet = SiteOrigin(scheme: "HTTPS", host: "Meet.Example", port: 0)
    private let space = UUID()
    private func record(
        _ permission: SitePermission = .camera, _ decision: SitePermissionDecision = .grantPersistently,
        id: UUID = UUID(), host: String = "meet.example", detail: String? = nil, time: Double = 808529885.001641
    ) -> PermissionRecord {
        PermissionRecord(
            id: id, spaceID: space, origin: SiteOrigin(scheme: "https", host: host, port: 443), permission: permission,
            detail: detail, decision: decision, modifiedAt: time)
    }
    func testAllCombinedCaptureAnswersMatchTheCrestLedger() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
            "Fixtures/permissions-crest-baseline.json")
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String]])
        XCTAssertEqual(rows.count, 125)
        for row in rows {
            var ledger = PermissionLedger()
            for (permission, name) in zip([SitePermission.camera, .microphone, .cameraAndMicrophone], row.prefix(3)) {
                _ = try ledger.set(space, meet, permission, nil, XCTUnwrap(SitePermissionDecision.named(name)))
            }
            XCTAssertEqual(
                [SitePermission.camera, .microphone, .cameraAndMicrophone].map {
                    ledger.mediaDecision(space, meet, $0).name
                }, Array(row.suffix(3)), row.description)
        }
    }
    func testChoicesAreScopedBySpaceOriginCapabilityAndExactDetail() throws {
        var ledger = PermissionLedger()
        _ = try ledger.set(space, meet, .camera, nil, .grantForSession)
        XCTAssertEqual(ledger.decision(space, meet, .camera), .grantForSession)
        XCTAssertEqual(ledger.decision(UUID(), meet, .camera), .ask)
        XCTAssertEqual(ledger.decision(space, meet, .microphone), .ask)
        XCTAssertEqual(ledger.decision(space, SiteOrigin(scheme: "https", host: meet.host, port: 8443), .camera), .ask)
        _ = try ledger.set(space, meet, .externalApplications, nil, .denyPersistently)
        _ = try ledger.set(space, meet, .externalApplications, "mailto", .grantPersistently)
        XCTAssertEqual(ledger.decision(space, meet, .externalApplications, "mailto"), .grantPersistently)
        XCTAssertEqual(ledger.decision(space, meet, .externalApplications, "zoommtg"), .denyPersistently)
        _ = try ledger.set(space, meet, .externalApplications, "mailto", .ask)
        XCTAssertEqual(ledger.decision(space, meet, .externalApplications, "mailto"), .denyPersistently)
        XCTAssertEqual(ledger.decision(space, meet, .externalApplications, ""), .ask)
    }
    func testSessionOverrideDoesNotReplaceSavedChoiceAndResetRecordKeepsTheOverride() throws {
        var ledger = PermissionLedger()
        let saved = record()
        ledger.restore([saved])
        XCTAssertFalse(try ledger.set(space, meet, .camera, nil, .denyForSession))
        XCTAssertEqual(ledger.records, [saved])
        ledger.restore(ledger.records)
        XCTAssertEqual(ledger.decision(space, meet, .camera), .denyForSession)
        var restarted = PermissionLedger()
        restarted.restore(ledger.records)
        XCTAssertEqual(restarted.decision(space, meet, .camera), .grantPersistently)
        XCTAssertEqual(ledger.reset(saved.id), saved)
        XCTAssertNil(ledger.reset(saved.id))
        XCTAssertEqual(ledger.decision(space, meet, .camera), .denyForSession)
        XCTAssertFalse(ledger.resetSpace(space))
        XCTAssertEqual(ledger.decision(space, meet, .camera), .ask)
    }
    func testPersistentEditsKeepIdentityAndExactTimestamp() throws {
        var ledger = PermissionLedger()
        let saved = record()
        ledger.restore([saved])
        let timestamp = 780000000.1234567
        XCTAssertTrue(try ledger.set(space, meet, .camera, nil, .denyPersistently, now: timestamp))
        XCTAssertEqual(ledger.records.first?.id, saved.id)
        XCTAssertEqual(ledger.records.first?.modifiedAt.bitPattern, timestamp.bitPattern)
    }
    func testRestoreFiltersMalformedRepeatedAndSystemGrantedRecords() {
        let first = record()
        var ledger = PermissionLedger()
        ledger.restore([
            first, record(id: first.id, host: "other.example"), record(), record(.microphone, .grantForSession),
            record(.location, detail: ""), record(.screenSharing), record(.popups, time: .infinity),
            record(.notifications, id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!),
        ])
        XCTAssertEqual(ledger.records, [first])
    }
    func testLimitsAndInvalidAnswersLeaveChoicesUntouched() throws {
        var ledger = PermissionLedger()
        ledger.restore((0..<PermissionLedger.maximumRecords).map { record(host: "host\($0).example") })
        let before = ledger.records
        XCTAssertThrowsError(try ledger.set(space, meet, .camera, nil, .grantPersistently)) {
            XCTAssertEqual($0 as? PermissionFailure, .limitReached)
        }
        XCTAssertThrowsError(try ledger.set(space, meet, .screenSharing, nil, .grantForSession)) {
            XCTAssertEqual($0 as? PermissionFailure, .invalidGrant)
        }
        XCTAssertThrowsError(
            try ledger.set(space, meet, .camera, String(repeating: "😀", count: 129), .grantPersistently)
        ) { XCTAssertEqual($0 as? PermissionFailure, .invalidDetail) }
        XCTAssertThrowsError(
            try ledger.set(space, SiteOrigin(scheme: "https", host: "", port: 443), .camera, nil, .grantPersistently)
        ) { XCTAssertEqual($0 as? PermissionFailure, .invalidOrigin) }
        XCTAssertEqual(ledger.records, before)
        XCTAssertTrue(try ledger.set(space, before[0].origin, .camera, nil, .denyPersistently))
    }
    func testDisplayOrderUsesNumericHostsThenCapabilityAndDetail() {
        let records = [
            record(.camera, host: "host10.example"), record(.camera, host: "host9.example"),
            record(.popups, host: "b.example"), record(.externalApplications, host: "b.example", detail: "tel"),
            record(.externalApplications, host: "b.example", detail: "mailto"),
            record(.automaticDownloads, host: "b.example"),
        ]
        XCTAssertEqual(
            records.sorted(by: PermissionLedger.precedes).map {
                "\($0.origin.host)/\($0.permission.name)/\($0.detail ?? "")"
            },
            [
                "b.example/automaticDownloads/", "b.example/externalApplications/mailto",
                "b.example/externalApplications/tel", "b.example/popups/", "host9.example/camera/",
                "host10.example/camera/",
            ])
    }
    func testCanonicalUnicodeSpellingsRemainSeparateChoices() throws {
        var ledger = PermissionLedger()
        let composed = SiteOrigin(scheme: "https", host: "é.example", port: 443)
        let decomposed = SiteOrigin(scheme: "https", host: "e\u{301}.example", port: 443)
        _ = try ledger.set(space, composed, .camera, nil, .grantPersistently)
        _ = try ledger.set(space, decomposed, .camera, nil, .denyPersistently)
        XCTAssertEqual(ledger.records.count, 2)
        XCTAssertEqual(ledger.decision(space, composed, .camera), .grantPersistently)
        XCTAssertEqual(ledger.decision(space, decomposed, .camera), .denyPersistently)
    }
}
