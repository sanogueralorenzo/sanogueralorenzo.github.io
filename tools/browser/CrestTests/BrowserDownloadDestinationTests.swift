import Foundation
import XCTest

@testable import Crest

final class BrowserDownloadDestinationTests: XCTestCase {
    @MainActor
    func testUnavailableSavedFolderIsRetainedForRecoveryInsteadOfFallingBackToDownloads() async {
        let preferences = BrowserPlatformDownloadPreferences.shared
        let spaceID = UUID()
        defer { preferences.clearDirectory(for: spaceID) }
        preferences.setDirectoryMetadata(bookmark: Data([1, 2, 3]), displayName: "Work Files", for: spaceID)
        let resolution = await BrowserPlatformDownloadDirectory.resolve(
            suggestedFilename: "report.txt", spaceID: spaceID)
        guard resolution is BrowserDownloadFolderUnavailable else {
            XCTFail("A broken saved folder must not silently redirect a download.")
            return
        }
        XCTAssertEqual(preferences.directoryDisplayName(for: spaceID), "Work Files")
    }

    func testUsesTheSuggestedFilenameWhenItIsAvailable() {
        let directory = URL(fileURLWithPath: "/Downloads", isDirectory: true)

        let destination = BrowserDownloadDestination.availableURL(
            suggestedFilename: "report.pdf",
            directory: directory,
            fileExists: { _ in false }
        )

        XCTAssertEqual(destination, directory.appendingPathComponent("report.pdf"))
    }

    func testAddsAStableNumericSuffixWithoutChangingTheExtension() {
        let directory = URL(fileURLWithPath: "/Downloads", isDirectory: true)
        let occupied = Set(["report.pdf", "report 1.pdf"])

        let destination = BrowserDownloadDestination.availableURL(
            suggestedFilename: "report.pdf",
            directory: directory,
            fileExists: { occupied.contains($0.lastPathComponent) }
        )

        XCTAssertEqual(destination, directory.appendingPathComponent("report 2.pdf"))
    }

    func testRemovesPathTraversalFromASuggestedFilename() {
        let directory = URL(fileURLWithPath: "/Downloads", isDirectory: true)

        let destination = BrowserDownloadDestination.availableURL(
            suggestedFilename: "../../secret.txt",
            directory: directory,
            fileExists: { _ in false }
        )

        XCTAssertEqual(destination, directory.appendingPathComponent("secret.txt"))
    }

    func testRemovesWindowsTraversalControlCharactersAndHiddenEdges() {
        XCTAssertEqual(
            BrowserDownloadDestination.safeFilename(from: "..\\..\\.pay\u{0}load.txt. "),
            "payload.txt"
        )
        XCTAssertEqual(BrowserDownloadDestination.safeFilename(from: "../.."), "download")
    }

    func testFilenameFitsTheFilesystemByteLimitWithoutDroppingANormalExtension() {
        let filename = String(repeating: "🌌", count: 100) + ".pdf"

        let sanitized = BrowserDownloadDestination.safeFilename(from: filename)

        XCTAssertLessThanOrEqual(sanitized.utf8.count, BrowserDownloadDestination.maximumFilenameByteCount)
        XCTAssertEqual((sanitized as NSString).pathExtension, "pdf")
    }

    func testRemovesDirectionChangingUnicodeFromTheVisibleFilename() {
        let deceptive = "invoice.pdf\u{202E}ppa"

        XCTAssertEqual(BrowserDownloadDestination.safeFilename(from: deceptive), "invoice.pdfppa")
    }

    @MainActor
    func testDownloadPreferencesStayLocalToTheirSpace() throws {
        let suiteName = "BrowserDownloadDestinationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = BrowserPlatformDownloadPreferences(defaults: defaults)
        let work = UUID()
        let personal = UUID()

        preferences.setAsksWhereToSave(true, for: work)
        preferences.setDirectoryMetadata(
            bookmark: Data([0x43, 0x52, 0x45, 0x53, 0x54]),
            displayName: "Work Downloads",
            for: work
        )

        XCTAssertTrue(preferences.asksWhereToSave(for: work))
        XCTAssertEqual(preferences.directoryDisplayName(for: work), "Work Downloads")
        XCTAssertFalse(preferences.asksWhereToSave(for: personal))
        XCTAssertNil(preferences.directoryDisplayName(for: personal))
    }
}
