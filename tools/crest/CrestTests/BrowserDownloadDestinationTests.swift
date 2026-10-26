import Foundation
import XCTest

@testable import Crest

final class BrowserDownloadDestinationTests: XCTestCase {
    @MainActor
    func testOrdinaryDownloadsUseDownloadsWithoutRequestingFolderAccess() async throws {
        let resolution = await BrowserPlatformDownloadDirectory.resolve(suggestedFilename: "report.txt")
        let destination = try XCTUnwrap(resolution as? BrowserDownloadDestinationChosen)
        XCTAssertEqual(
            destination.url.deletingLastPathComponent(),
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first)
        XCTAssertNil(destination.securityScopedURL)
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

}
