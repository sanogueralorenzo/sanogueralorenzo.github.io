import AppKit
import CoreServices
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WebKit
import XCTest

@testable import Crest

final class BrowserDownloadTransferTests: XCTestCase {
    @MainActor
    func testNativeSaveRequiresApprovalForDeceptiveFilenameBeforeSelectingDestination() async throws {
        var approvalRequests = 0
        var destinationRequests = 0
        let center = BrowserDownloadCenter(
            approveRiskyDownload: { assessment, _, spaceName, _ in
                approvalRequests += 1
                XCTAssertTrue(assessment.reasons.contains(.deceptiveFilename))
                XCTAssertEqual(spaceName, "Work")
                return false
            },
            resolveDownloadDestination: { _, _, _ in
                destinationRequests += 1
                return .cancelled
            })
        await center.saveData(
            try nativeSavePDFFixture(), suggestedFilename: "invoice\u{202E}fdp.sh", mimeType: "application/pdf",
            originatingURL: URL(string: "https://pdf.crest.test/")!,
            assignment: BrowserSpaceRuntimeAssignment(spaceID: UUID(), profileID: UUID()), spaceName: "Work")
        XCTAssertEqual(approvalRequests, 1)
        XCTAssertEqual(destinationRequests, 0)
        guard case .canceled = center.items.first?.phase else { return XCTFail("Rejected save must be canceled") }
    }

    private func nativeSavePDFFixture() throws -> Data {
        let data = NSMutableData()
        var bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        context.beginPDFPage(nil)
        context.fill(CGRect(x: 10, y: 10, width: 25, height: 25))
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    func testFinishingAWebDownloadAppliesSystemQuarantineMetadata() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let staging = directory.appendingPathComponent("staging/source.txt")
        let destination = directory.appendingPathComponent("Downloads/report.txt")
        let sourceURL = try XCTUnwrap(URL(string: "https://downloads.example/report.txt"))
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: staging.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("hello".utf8).write(to: staging)

        try BrowserDownloadTransfer.finish(
            from: staging,
            to: destination,
            quarantine: BrowserDownloadQuarantine(
                sourceURL: sourceURL,
                timestamp: Date(timeIntervalSince1970: 1_000),
                agentName: "Crest Tests",
                agentBundleIdentifier: "com.pauldavis.crest.tests"
            )
        )

        let properties = try destination.resourceValues(forKeys: [.quarantinePropertiesKey])
            .quarantineProperties
        XCTAssertNotNil(properties)
        XCTAssertFalse((properties?["LSQuarantineAgentName"] as? String)?.isEmpty ?? true)
    }

}
