import Foundation
import Network
import UIKit
import WebKit
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserInteropTests: XCTestCase {

    func testPrivateDisguisedExecutableDownloadWaitsForItsSpaceAndCancellationWritesNothing() async throws {
        let filename = "crest-private-\(UUID().uuidString).jpg"
        let server = try MobileDownloadHTTPServer(
            payload: Data("potentially dangerous private download".utf8),
            filename: filename,
            mimeType: "application/x-mach-binary"
        )
        let port = try await server.start()
        let sourceURL = try XCTUnwrap(URL(string: "http://localhost:\(port)/\(filename)"))
        let destination = URL.documentsDirectory
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent(filename)
        let browser = BrowserStore.privateBrowsing(core: .hostingPages())
        let permissionCenter = BrowserSitePermissionCenter(core: browser.core)
        let pages = MobileBrowserPageStore(
            browser: browser,
            browsingMode: .privateBrowsing,
            permissionCenter: permissionCenter
        )
        let privateSpace = try XCTUnwrap(browser.shownSpace)
        let sourceOrigin = try XCTUnwrap(SiteOrigin(url: sourceURL))
        permissionCenter.setDecision(
            .grantForSession,
            for: .automaticDownloads,
            origin: sourceOrigin,
            in: privateSpace.id
        )
        pages.select()
        let page = try XCTUnwrap(pages.activePage)
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: destination)
            pages.downloadRiskConfirmation.cancelAll()
            pages.closePrivateBrowsingSession(browser.spaceModels.map(BrowserSpaceRuntimeAssignment.init(space:)))
        }

        // User initiation bypasses the extra prompt for ordinary installers.
        // An executable disguised as an image still requires confirmation.
        page.webView.startDownload(using: URLRequest(url: sourceURL)) { download in
            page.webKitPage.startDownload(download, isUserInitiated: true)
        }

        try await waitUntil(timeout: 5) {
            pages.downloadRiskConfirmation.request != nil
        }
        let request = try XCTUnwrap(pages.downloadRiskConfirmation.request)
        XCTAssertEqual(request.assessment.sanitizedFilename, filename)
        XCTAssertTrue(request.assessment.reasons.contains(.dangerousTypeMismatch))
        XCTAssertEqual(request.spaceName, "Private")
        XCTAssertEqual(request.sourceLabel, "localhost")
        XCTAssertEqual(pages.downloadCenter.items.first?.phase, .awaitingApproval)
        XCTAssertEqual(
            pages.downloadCenter.items.first?.profileID,
            privateSpace.profileID
        )

        pages.downloadRiskConfirmation.cancel()

        try await waitUntil(timeout: 5) {
            pages.downloadCenter.items.contains {
                if case .canceled = $0.phase { return true }
                return false
            }
        }
        XCTAssertEqual(pages.downloadCenter.items.first?.phase, .canceled)
        XCTAssertEqual(
            pages.downloadCenter.items.first?.message,
            "Canceled before downloading a potentially dangerous file."
        )
        XCTAssertNil(pages.downloadCenter.items.first?.destinationURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testADownloadFromAnotherSiteFollowsThePagesAutomaticDownloadChoice() async throws {
        let filename = "crest-cdn-\(UUID().uuidString).payload"
        let server = try MobileDownloadHTTPServer(
            payload: Data("download served by another site".utf8),
            filename: filename,
            pageHTML: "<!doctype html><title>Release</title>"
        )
        let port = try await server.start()
        let pageURL = try XCTUnwrap(URL(string: "http://localhost:\(port)/page"))
        // The file comes from another site, as a release page's files come
        // from its CDN.
        let fileURL = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/\(filename)"))
        let profile = BrowsingProfile()
        let tab = TabState.Seed(title: "Release", url: nil, placement: .current)
        let space = SpaceState.Seed(
            profileID: profile.id,
            name: "Download Space",
            symbol: "arrow.down.circle",
            accent: .teal,
            folders: [],
            tabs: [tab]
        )
        let browser = BrowserStore.hostingPages(SessionState.Seed(spaces: [space]))
        let permissionCenter = BrowserSitePermissionCenter(core: browser.core)
        let downloads = MobileBrowserDownloads(core: browser.core, permissionCenter: permissionCenter)
        let page = try XCTUnwrap(
            browser.openWebKitPage(in: space.id, for: tab.id).map { opened in
                MobileBrowserPage(
                    corePage: opened.core,
                    webKitPage: opened.webKit,
                    tab: browser.pageTab(tab.id, in: space.id),
                    space: browser.hostedSpace(space.id),
                    downloadCenter: downloads.center,
                    permissionCenter: permissionCenter
                )
            }
        )
        permissionCenter.setDecision(
            .denyPersistently,
            for: .automaticDownloads,
            origin: try XCTUnwrap(SiteOrigin(url: pageURL)),
            in: space.id
        )
        defer { server.stop() }

        page.webView.load(URLRequest(url: pageURL))
        try await waitUntil(timeout: 5) {
            page.webView.backForwardList.currentItem?.url == pageURL && !page.webView.isLoading
        }
        // While this navigation becomes a download, the web view's URL is
        // already the file's; the page's site still owns the choice.
        page.webView.load(URLRequest(url: fileURL))

        // In the Simulator WebKit takes four to five seconds to hand a
        // navigation to another site over as a download.
        let center = downloads.center
        try await waitUntil(timeout: 15) {
            center.items.contains { $0.phase != .preparing }
        }
        XCTAssertEqual(center.items.first?.phase, .blockedAutomaticDownload)
        await Self.removeDataStore(profile.id)
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: @escaping @MainActor () async throws -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while try await !condition() {
            if Date() >= deadline {
                throw MobileBrowserInteropTestError.timedOutWaitingForDownload
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private static func removeDataStore(_ identifier: UUID) async {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.remove(forIdentifier: identifier) { _ in continuation.resume() }
        }
    }

    // MARK: - Archived tab state

    // MARK: - Idle unloading

    // MARK: - Relocking a protected Space
}

private enum MobileBrowserInteropTestError: Error {
    case timedOutWaitingForDownload
    case listenerFailed
}

private final class MobileDownloadHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.pauldavis.crest.tests.mobile-download")
    private let responseData: Data
    private let unauthorizedResponseData: Data
    private let requiredAuthorizationHeader: String?
    /// The page `GET /page` answers with, when the server has one.
    private let pageResponseData: Data?

    init(
        payload: Data,
        filename: String,
        mimeType: String = "application/octet-stream",
        basicAuthentication: (username: String, password: String)? = nil,
        pageHTML: String? = nil
    ) throws {
        listener = try NWListener(using: .tcp, on: .any)
        pageResponseData = pageHTML.map { html in
            Data(
                """
                HTTP/1.1 200 OK\r
                Content-Type: text/html\r
                Content-Length: \(html.utf8.count)\r
                Connection: close\r
                \r
                \(html)
                """.utf8
            )
        }
        let header = """
            HTTP/1.1 200 OK\r
            Content-Type: \(mimeType)\r
            Content-Disposition: attachment; filename="\(filename)"\r
            Content-Length: \(payload.count)\r
            Connection: close\r
            \r

            """
        responseData = Data(header.utf8) + payload
        unauthorizedResponseData = Data(
            """
            HTTP/1.1 401 Unauthorized\r
            WWW-Authenticate: Basic realm="Crest Tests"\r
            Content-Length: 0\r
            Connection: close\r
            \r

            """.utf8
        )
        requiredAuthorizationHeader = basicAuthentication.map {
            let encoded = Data("\($0.username):\($0.password)".utf8).base64EncodedString()
            return "authorization: basic \(encoded)".lowercased()
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.serve(connection)
        }
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = listener.port else {
                        listener.stateUpdateHandler = nil
                        continuation.resume(throwing: MobileBrowserInteropTestError.listenerFailed)
                        return
                    }
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: port.rawValue)
                case .failed:
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: MobileBrowserInteropTestError.listenerFailed)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
    }

    private func serve(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard state == .ready, let self, let connection else { return }
            connection.receive(minimumIncompleteLength: 1, maximumLength: 32_768) {
                [weak self, weak connection] data, _, _, error in
                guard let self, let connection, data != nil, error == nil else {
                    connection?.cancel()
                    return
                }
                let request = data.flatMap { String(data: $0, encoding: .utf8) }?.lowercased()
                let response =
                    if let pageResponseData, request?.hasPrefix("get /page ") == true {
                        pageResponseData
                    } else {
                        requiredAuthorizationHeader.map {
                            request?.contains($0) == true ? responseData : unauthorizedResponseData
                        } ?? responseData
                    }
                connection.send(
                    content: response,
                    contentContext: .defaultMessage,
                    isComplete: true,
                    completion: .contentProcessed { _ in connection.cancel() }
                )
            }
        }
        connection.start(queue: queue)
    }
}
