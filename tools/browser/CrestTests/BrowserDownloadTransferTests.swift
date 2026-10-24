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
    func testNativeSavePreservesDisplayedPDFBytesDestinationConsentAndProfileOwnership() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "crest-native-save-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let assignment = BrowserSpaceRuntimeAssignment(spaceID: UUID(), profileID: UUID())
        let source = URL(string: "https://pdf.crest.test/authenticated/redirected")!
        let destination = root.appending(path: "chosen.pdf")
        let data = try nativeSavePDFFixture()
        var destinationRequests = 0
        let center = BrowserDownloadCenter(resolveDownloadDestination: { filename, spaceID, forcesPrompt in
            destinationRequests += 1
            XCTAssertEqual(filename, "displayed.pdf")
            XCTAssertEqual(spaceID, assignment.spaceID)
            XCTAssertFalse(forcesPrompt)
            return .destination(destination, securityScopedURL: nil)
        })
        let itemID = await center.saveData(
            data, suggestedFilename: "../displayed.pdf", mimeType: "application/pdf",
            originatingURL: source, assignment: assignment, spaceName: "Private")
        let item = try XCTUnwrap(center.items(for: assignment.profileID).first)
        XCTAssertEqual(destinationRequests, 1)
        XCTAssertEqual(item.id, itemID)
        XCTAssertEqual(item.phase, .finished)
        XCTAssertEqual(item.filename, "chosen.pdf")
        XCTAssertTrue(center.items(for: UUID()).isEmpty)
        let saved = try Data(contentsOf: destination)
        XCTAssertEqual(saved, data)
        let document = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: saved as CFData)!))
        XCTAssertEqual(document.numberOfPages, 1)
        let quarantine = try XCTUnwrap(
            destination.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties)
        XCTAssertEqual(quarantine[kLSQuarantineTypeKey as String] as? String, kLSQuarantineTypeWebDownload as String)
    }

    @MainActor
    func testNativeSaveReportsDestinationCancellationUnavailabilityAndWriteFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "crest-native-save-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let occupied = root.appending(path: "occupied.pdf")
        let original = Data("Existing user file".utf8)
        try original.write(to: occupied)
        let resolutions: [any BrowserPlatformDownloadResolution] = [
            .cancelled, .unavailable, .destination(occupied, securityScopedURL: nil),
        ]
        for (index, resolution) in resolutions.enumerated() {
            let center = BrowserDownloadCenter(resolveDownloadDestination: { _, _, _ in resolution })
            await center.saveData(
                try nativeSavePDFFixture(), suggestedFilename: "displayed.pdf", mimeType: "application/pdf",
                originatingURL: URL(string: "https://pdf.crest.test/")!,
                assignment: BrowserSpaceRuntimeAssignment(spaceID: UUID(), profileID: UUID()), spaceName: "Work")
            let item = try XCTUnwrap(center.items.first)
            if index == 0 {
                guard item.phase == .canceled else { return XCTFail("Destination cancellation must remain canceled") }
            } else {
                guard item.phase == .failed else { return XCTFail("Destination errors must be visible") }
                XCTAssertFalse(item.message?.isEmpty ?? true)
            }
        }
        XCTAssertEqual(try Data(contentsOf: occupied), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["occupied.pdf"])
    }

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

    @MainActor
    func testNativeSaveCannotWriteAfterCancellationOrOwningSpaceRemovalWhileChoosingDestination() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "crest-native-save-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        for removesSpace in [false, true] {
            var reply: CheckedContinuation<any BrowserPlatformDownloadResolution, Never>?
            let center = BrowserDownloadCenter(resolveDownloadDestination: { _, _, _ in
                await withCheckedContinuation { reply = $0 }
            })
            let assignment = BrowserSpaceRuntimeAssignment(spaceID: UUID(), profileID: UUID())
            let data = try nativeSavePDFFixture()
            let saving = Task {
                await center.saveData(
                    data, suggestedFilename: "displayed.pdf", mimeType: "application/pdf",
                    originatingURL: URL(string: "https://pdf.crest.test/")!,
                    assignment: assignment, spaceName: "Work")
            }
            try await waitForDownloadCondition { reply != nil }
            let item = try XCTUnwrap(center.items.first)
            // Another Space's cleanup must not cancel or reassign this save.
            center.deleteRecords(profileID: UUID(), spaceID: UUID())
            XCTAssertEqual(center.items.first?.id, item.id)
            if removesSpace {
                center.deleteRecords(profileID: assignment.profileID, spaceID: assignment.spaceID)
            } else {
                center.cancel(item.id)
            }
            reply?.resume(returning: .destination(root.appending(path: "late.pdf"), securityScopedURL: nil))
            _ = await saving.value
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
            if removesSpace {
                XCTAssertTrue(center.items.isEmpty)
            } else {
                guard case .canceled = center.items.first?.phase else {
                    return XCTFail("Late consent resurrected a canceled save")
                }
            }
        }
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

    @MainActor
    func testAutomaticDownloadsUseSiteControlsAndDismissalDoesNotSaveABlock() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "crest-download-permissions-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // A page WebKit's binding built for the core, whose downloads the core
        // records and whose file places this answers.
        let space = try XCTUnwrap(SessionState.Seed.preview.spaces.first)
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]))
        let permissions = BrowserSitePermissionCenter(core: browser.core)
        let prompts = BrowserDownloadPrompts(
            core: browser.core, approve: { _, _ in false },
            resolveDestination: { filename, _, _ in
                .destination(root.appending(path: "\(UUID())-\(filename)"), securityScopedURL: nil)
            })
        let opened = try XCTUnwrap(
            browser.openWebKitPage(
                in: space.id, for: nil))
        let page = BrowserPage(
            corePage: opened.core, webKitPage: opened.webKit, dialogPresenter: BrowserDialogPresenter(),
            downloadCenter: BrowserDownloadCenter(core: browser.core), permissionCenter: permissions,
            spaceID: space.id, profileID: space.profileID, spaceName: space.settings.name, openNewTab: { _ in })
        defer {
            page.release(keepingState: false)
            withExtendedLifetime(prompts) {}
        }
        page.sitePermissionRequests.setPresentationAvailable(true)
        let web = page.webView
        let url = try XCTUnwrap(URL(string: "https://downloads.crest.test/"))
        web.loadSimulatedRequest(
            URLRequest(url: url),
            responseHTML: """
                <title>Downloads</title><script>
                window.pendingDownloads = 0;
                setInterval(() => {
                  if (!window.pendingDownloads) return;
                  window.pendingDownloads--;
                  const link = document.createElement('a');
                  link.href = 'data:text/plain;base64,aGVsbG8=';
                  link.download = 'hello.txt';
                  link.click();
                }, 100);
                </script>
                """)
        let origin = try XCTUnwrap(SiteOrigin(url: url))
        try await waitForDownloadCondition { web.url == url && !web.isLoading }
        func start() async throws {
            _ = try await web.callAsyncJavaScript(
                "window.pendingDownloads++;",
                arguments: [:], in: nil, contentWorld: .page)
        }
        func finished() -> Int { browser.core.state.downloads.filter { $0.phase == .finished }.count }

        // The site's first file under Ask goes through without asking.
        try await start()
        try await waitForDownloadCondition { finished() == 1 }
        XCTAssertNil(page.sitePermissionRequests.current)

        // A second asks; dismissing it blocks the file and saves nothing.
        try await start()
        try await waitForDownloadCondition { page.sitePermissionRequests.current != nil }
        XCTAssertEqual(page.sitePermissionRequests.current?.permission, .automaticDownloads)
        XCTAssertEqual(page.sitePermissionRequests.current?.origin, origin)
        page.sitePermissionRequests.cancelAll()
        try await waitForDownloadCondition {
            browser.core.state.downloads.contains { $0.phase == .blockedAutomaticDownload }
        }
        XCTAssertEqual(permissions.decision(for: .automaticDownloads, origin: origin, in: space.id), .ask)
        XCTAssertTrue(permissions.records(in: space.id).isEmpty)

        // Allowing and remembering it lets this file and the next through.
        try await start()
        try await waitForDownloadCondition { page.sitePermissionRequests.current != nil }
        page.sitePermissionRequests.resolve(
            try XCTUnwrap(page.sitePermissionRequests.current?.id), response: .grantPersistently)
        try await waitForDownloadCondition { finished() == 2 }
        try await start()
        try await waitForDownloadCondition { finished() == 3 }
        XCTAssertNil(page.sitePermissionRequests.current)
        XCTAssertEqual(permissions.records(in: space.id).first?.decision, .grantPersistently)
    }

    @MainActor
    private func waitForDownloadCondition(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertTrue(condition())
    }

    func testStagingURLLivesInsideTheAppOwnedDirectory() {
        let directory = URL(fileURLWithPath: "/Application Support/Crest/Download Staging", isDirectory: true)
        let itemID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

        let url = BrowserDownloadTransfer.stagingURL(
            itemID: itemID,
            suggestedFilename: "report.pdf",
            directory: directory
        )

        XCTAssertEqual(url.deletingLastPathComponent(), directory)
        XCTAssertEqual(url.pathExtension, "pdf")
        XCTAssertTrue(url.lastPathComponent.contains(itemID.uuidString))
    }

    func testFinishingMovesTheStagedFileToItsVisibleDestination() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let staging = directory.appendingPathComponent("staging/source.txt")
        let destination = directory.appendingPathComponent("Downloads/report.txt")
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

        try BrowserDownloadTransfer.finish(from: staging, to: destination)

        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertEqual(try Data(contentsOf: destination), Data("hello".utf8))
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
