import Foundation
import XCTest

@testable import Crest

final class NativeDownloadPolicyTests: XCTestCase {
    func testRiskRulesRetainInstallerDisguiseAndMismatchedTypeDecisions() throws {
        for filename in ["update.pkg", "tool.command", "setup.EXE", "profile.mobileconfig", "script.PS1"] {
            let facts = facts(filename)
            XCTAssertEqual(
                try DownloadRisk(facts: facts, isUserInitiated: false).answer().assessment.reasons,
                [.executableOrInstaller])
            XCTAssertFalse(try DownloadRisk(facts: facts, isUserInitiated: true).answer().requiresConfirmation)
        }
        for filename in [
            "photo.jpg\u{202E}gpj.command", "invoice\u{200B}.pdf", "\u{FEFF}notes.txt", "list\u{2067}.txt",
        ] {
            let value = facts(filename, sanitized: "renamed.txt")
            XCTAssertEqual(
                try DownloadRisk(facts: value, isUserInitiated: true).answer().assessment.reasons, [.deceptiveFilename])
            XCTAssertTrue(try DownloadRisk(facts: value, isUserInitiated: true).answer().requiresConfirmation)
        }
        let mismatch = DownloadRiskFacts(
            suggestedFilename: "photo.jpg", sanitizedFilename: "photo.jpg", mimeType: "application/x-executable",
            extensionRunsCode: false, mimeTypeRunsCode: false, typesRelated: false)
        XCTAssertEqual(
            try DownloadRisk(facts: mismatch, isUserInitiated: true).answer().assessment.reasons,
            [.executableOrInstaller, .dangerousTypeMismatch])
    }

    func testAutomaticDownloadsKeepTheOneFileAllowanceAndRespectSavedDecisions() {
        func check(
            _ decision: SitePermissionDecision = .ask, gesture: Bool = false, retry: Bool = false, used: Bool = false
        ) -> AutomaticDownloadVerdict {
            AutomaticDownloadCheck(
                userInitiated: gesture, userApprovedRetry: retry, savedDecision: decision,
                hasAllowedAutomaticDownload: used
            ).verdict
        }
        XCTAssertEqual(check().action, .allow)
        XCTAssertTrue(check().hasAllowedAutomaticDownload)
        XCTAssertEqual(check(used: true).action, .requestPermission)
        XCTAssertEqual(check(gesture: true, used: true).action, .allow)
        XCTAssertFalse(check(gesture: true, used: true).hasAllowedAutomaticDownload)
        for decision in SitePermissionDecision.all {
            XCTAssertEqual(
                check(decision, used: true).action,
                decision.grants ? .allow : decision.denies ? .deny : .requestPermission)
            XCTAssertEqual(check(decision, gesture: true, used: true).action, .allow)
            XCTAssertEqual(check(decision, retry: true, used: true).action, .allow)
        }
    }

    func testTelemetryKeepsBytesMonotonicDiscardsDisprovedTotalsAndResetsRatesOnPause() throws {
        var reading = try DownloadTransferEstimator.initial.sample(
            completed: 0, total: 100, fraction: 0, paused: false, uptime: 0)
        reading = try reading.estimator.sample(completed: 10, total: 100, fraction: 0, paused: false, uptime: 1)
        XCTAssertEqual(reading.telemetry.bytesPerSecond, 10)
        XCTAssertEqual(reading.telemetry.estimatedTimeRemaining, 9)
        reading = try reading.estimator.sample(completed: 5, total: 100, fraction: 0, paused: false, uptime: 2)
        XCTAssertEqual(reading.telemetry.bytesReceived, 10)
        reading = try reading.estimator.sample(completed: 20, total: 15, fraction: 0.2, paused: false, uptime: 3)
        XCTAssertNil(reading.telemetry.totalBytes)
        XCTAssertTrue(reading.estimator.totalIsUnreliable)
        reading = try reading.estimator.sample(completed: 20, total: 100, fraction: 0.2, paused: true, uptime: 4)
        XCTAssertNil(reading.telemetry.totalBytes)
        XCTAssertNil(reading.telemetry.bytesPerSecond)
        XCTAssertNil(reading.telemetry.estimatedTimeRemaining)
        reading = try reading.estimator.sample(completed: 20, total: 100, fraction: 0.2, paused: false, uptime: 5)
        XCTAssertNil(reading.telemetry.bytesPerSecond)
        reading = try reading.estimator.sample(completed: 30, total: 100, fraction: 0.3, paused: false, uptime: 6)
        XCTAssertEqual(reading.telemetry.bytesPerSecond, 10)
        XCTAssertThrowsError(
            try reading.estimator.sample(completed: 30, total: 100, fraction: 0, paused: false, uptime: .nan))
        XCTAssertEqual(
            try DownloadTransferEstimator.initial.sample(
                completed: -10, total: 0, fraction: .infinity, paused: false, uptime: 0
            ).progress, 0)
    }

    private func facts(_ filename: String, sanitized: String? = nil) -> DownloadRiskFacts {
        DownloadRiskFacts(
            suggestedFilename: filename, sanitizedFilename: sanitized ?? filename, mimeType: "application/octet-stream",
            extensionRunsCode: false, mimeTypeRunsCode: false, typesRelated: nil)
    }
}
