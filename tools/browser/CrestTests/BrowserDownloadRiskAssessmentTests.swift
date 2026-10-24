import Foundation
import XCTest

@testable import Crest

/// The core owns the risk rules; this covers the platform facts the Swift
/// adapter supplies from the system type registry.
@MainActor
final class BrowserDownloadRiskAssessmentTests: XCTestCase {
    func testDangerousMIMEAndBenignExtensionMismatchIsExplicit() {
        let verdict = BrowserDownloadCenter().riskVerdict(
            suggestedFilename: "holiday.jpg",
            mimeType: "application/x-mach-binary",
            isUserInitiated: true
        )

        XCTAssertEqual(verdict.assessment.reasons, [.executableOrInstaller, .dangerousTypeMismatch])
        XCTAssertTrue(verdict.requiresConfirmation)
    }

    func testRegisteredScriptTypesRunCodeWithoutBeingListedByExtension() {
        let verdict = BrowserDownloadCenter().riskVerdict(
            suggestedFilename: "../../install.py",
            mimeType: "text/x-python-script",
            isUserInitiated: false
        )

        XCTAssertEqual(verdict.assessment.sanitizedFilename, "install.py")
        XCTAssertTrue(verdict.assessment.reasons.contains(.executableOrInstaller))
        XCTAssertTrue(verdict.requiresConfirmation)
    }
}
