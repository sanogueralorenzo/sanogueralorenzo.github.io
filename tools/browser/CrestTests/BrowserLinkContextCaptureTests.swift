import AppKit
import Foundation
import XCTest

@testable import Crest

final class BrowserLinkContextCaptureTests: XCTestCase {
    func testARecordedLinkIsHandedToExactlyOneMenu() throws {
        var policy = BrowserLinkContextCapture()
        policy.record(body: makeBody(href: "https://example.com/article"))

        XCTAssertEqual(
            policy.pendingLink,
            URL(string: "https://example.com/article"),
            "Reading without taking leaves the capture for the menu."
        )
        XCTAssertEqual(
            policy.take()?.linkURL,
            URL(string: "https://example.com/article")
        )
        XCTAssertNil(
            policy.take()?.linkURL,
            "A second menu must never inherit the first menu's link."
        )
        XCTAssertNil(policy.pendingLink)
    }

    func testARightClickWithoutALinkEmptiesTheSlot() {
        var policy = BrowserLinkContextCapture()
        policy.record(body: makeBody(href: "https://example.com/article"))
        policy.record(body: makeBody(href: nil))

        XCTAssertNil(
            policy.take()?.linkURL,
            "Plain content reports itself so the previous link cannot leak."
        )
    }

    func testAClosingMenuDropsAnUnusedCapture() {
        var policy = BrowserLinkContextCapture()
        policy.record(body: makeBody(href: "https://example.com/article"))
        policy.clear()

        XCTAssertNil(policy.pendingLink)
        XCTAssertNil(policy.take())
    }

    func testALaterRightClickReplacesAnEarlierCapture() throws {
        var policy = BrowserLinkContextCapture()
        policy.record(body: makeBody(href: "https://example.com/first"))
        policy.record(body: makeBody(href: "https://example.com/second"))

        XCTAssertEqual(
            policy.take()?.linkURL,
            URL(string: "https://example.com/second")
        )
    }

    func testACapturedLinkSurvivesAClearedPredecessor() throws {
        var policy = BrowserLinkContextCapture()
        policy.record(body: makeBody(href: "https://example.com/first"))
        policy.clear()
        policy.record(body: makeBody(href: "https://example.com/second"))

        XCTAssertEqual(
            policy.take()?.linkURL,
            URL(string: "https://example.com/second"),
            "Clearing retires the previous report, not the whole bridge."
        )
    }

    func testOnlyWebSchemesAreCaptured() {
        let refused = [
            "javascript:alert(1)",
            "data:text/html,<b>hi</b>",
            "file:///etc/passwd",
            "mailto:someone@example.com",
            "about:blank",
            "crest-extension-install://chrome-web-store/abc",
            "https:///no-host",
        ]
        for href in refused {
            var policy = BrowserLinkContextCapture()
            policy.record(body: makeBody(href: href))
            XCTAssertNil(
                policy.take()?.linkURL,
                "\(href) is not a destination the new-tab path would accept."
            )
        }
    }

    func testMalformedPayloadsAreRefused() {
        let refused: [Any] = [
            "https://example.com/article",
            ["version": 1] as [String: Any],
            ["version": 2, "href": "https://example.com/article"] as [String: Any],
            ["href": "https://example.com/article"] as [String: Any],
            ["version": 1, "href": 17] as [String: Any],
            ["version": "1", "href": "https://example.com/article"] as [String: Any],
            [
                "version": 1,
                "href": "https://example.com/\(String(repeating: "a", count: 4_096))",
            ] as [String: Any],
        ]
        for body in refused {
            var policy = BrowserLinkContextCapture()
            policy.record(body: body)
            XCTAssertNil(
                policy.take()?.linkURL,
                "A payload the script never sends must not reach the menu."
            )
        }
    }

    func testAMalformedPayloadStillRetiresTheCaptureBeforeIt() {
        var policy = BrowserLinkContextCapture()
        policy.record(body: makeBody(href: "https://example.com/article"))
        policy.record(body: "not a dictionary")

        XCTAssertNil(
            policy.take()?.linkURL,
            "A report Crest cannot read is still a new right-click."
        )
    }

    func testImageAndLinkFromTheSameRightClickAreConsumedTogether() throws {
        var policy = BrowserLinkContextCapture()
        policy.record(
            body: makeBody(
                href: "https://example.com/article",
                imageURL: "https://cdn.example.com/photo.webp"
            )
        )

        XCTAssertEqual(
            policy.pendingImage,
            URL(string: "https://cdn.example.com/photo.webp")
        )
        let context = try XCTUnwrap(policy.take())
        XCTAssertEqual(context.linkURL, URL(string: "https://example.com/article"))
        XCTAssertEqual(
            context.imageURL,
            URL(string: "https://cdn.example.com/photo.webp")
        )
        XCTAssertNil(policy.take(), "One menu consumes both destinations.")
    }

    func testImageCaptureAcceptsPageDownloadSchemesButRefusesExecutableOnes() {
        let accepted = [
            "https://cdn.example.com/photo.webp",
            "http://localhost/photo.png",
            "blob:https://example.com/00000000-0000-4000-8000-000000000001",
            "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==",
        ]
        for imageURL in accepted {
            var policy = BrowserLinkContextCapture()
            policy.record(body: makeBody(imageURL: imageURL))
            XCTAssertEqual(policy.take()?.imageURL?.absoluteString, imageURL)
        }

        let refused = [
            "javascript:alert(1)",
            "file:///etc/passwd",
            "mailto:someone@example.com",
            "about:blank",
            "https:///no-host",
            "data:image/png;base64,\(String(repeating: "a", count: 4_096))",
        ]
        for imageURL in refused {
            var policy = BrowserLinkContextCapture()
            policy.record(body: makeBody(imageURL: imageURL))
            XCTAssertNil(policy.take()?.imageURL)
        }
    }

    func testSelectionEditableAndFrameMetadataTravelWithTheFreshCapture()
        throws
    {
        var policy = BrowserLinkContextCapture()
        let documentURL = try XCTUnwrap(
            URL(string: "https://frame.example/editor")
        )
        policy.record(
            body: makeBody(
                selectionText: "selected words",
                isEditable: true
            ),
            documentURL: documentURL,
            isMainFrame: false
        )

        let context = try XCTUnwrap(policy.take())
        XCTAssertEqual(context.selectionText, "selected words")
        XCTAssertTrue(context.isEditable)
        XCTAssertEqual(context.documentURL, documentURL)
        XCTAssertFalse(context.isMainFrame)
        XCTAssertNil(policy.take())
    }

    @MainActor
    func testLinkDestinationTitleKeepsWebKitsActionAndShortcut() {
        let menu = NSMenu()
        let action = NSSelectorFromString("nativeOpenLink:")
        let target = NSObject()
        let item = NSMenuItem(title: "Localized native title", action: action, keyEquivalent: "t")
        item.identifier = NSUserInterfaceItemIdentifier("WKMenuItemIdentifierOpenLinkInNewWindow")
        item.target = target
        let download = NSMenuItem(title: "Download Linked File", action: nil, keyEquivalent: "")
        menu.items = [item, download]

        menu.relabelWebKitLinkDestination()

        XCTAssertEqual(item.title, String(localized: "Open Link in This Space"))
        XCTAssertEqual(item.action, action)
        XCTAssertTrue(item.target === target)
        XCTAssertEqual(item.keyEquivalent, "t")
        XCTAssertEqual(menu.items.count, 2)
        XCTAssertEqual(download.title, "Download Linked File")
    }

    @MainActor
    func testImageDownloadMenuLookupUsesWebKitsIdentifierInsteadOfItsTitle() {
        let menu = NSMenu()
        let unrelated = NSMenuItem(
            title: "Download Linked File",
            action: nil,
            keyEquivalent: ""
        )
        let imageDownload = NSMenuItem(
            title: "Localized Image Command",
            action: nil,
            keyEquivalent: ""
        )
        imageDownload.identifier = .webKitDownloadImage
        menu.items = [unrelated, imageDownload]

        XCTAssertTrue(
            menu.webKitDownloadImageItem === imageDownload
        )
    }

    /// Picking a row Crest put in an engine's context menu runs it on the
    /// page once the menu is done. AppKit must reach the row's own method: a
    /// row whose method shares a name with one of NSObject's raised and quit
    /// the app instead.
    @MainActor
    func testPickingACrestRowRunsItOnThePage() async throws {
        let host = RecordingContextMenuHost()
        let link = URL(string: "https://example.com/next")
        let space = BrowserPageContextMenuAction(
            kind: .space(UUID()), title: "Work", symbolName: "briefcase", linkURL: link, selectionText: nil
        ) { _, _, _ in true }
        let peek = BrowserPageContextMenuAction(
            kind: .peek, title: "Open Link in Peek", symbolName: "rectangle.on.rectangle", linkURL: link,
            selectionText: nil
        ) { _, _, _ in true }
        // The page's view outlives the menu, as the window keeps it; the rows
        // hold it weakly.
        let pageView = NSView()
        let menu = NSMenu()
        menu.addItem(withTitle: "Engine row", action: nil, keyEquivalent: "")
        BrowserPageContextMenu(actions: [space, peek], host: host, view: pageView).insert(into: menu)
        let ran = expectation(description: "Both rows ran")
        ran.expectedFulfillmentCount = 2
        host.performed = { _ in ran.fulfill() }

        // The other Spaces sit under one row, ahead of the page's own rows.
        let spaces = try XCTUnwrap(menu.items.first?.submenu)
        spaces.performActionForItem(at: 0)
        menu.performActionForItem(at: 1)
        await fulfillment(of: [ran], timeout: 2)

        XCTAssertEqual(host.ran.map(\.kind), [space.kind, peek.kind])
        withExtendedLifetime(pageView) {}
    }

    private func makeBody(
        href: String? = nil,
        imageURL: String? = nil,
        selectionText: String? = nil,
        isEditable: Bool = false
    ) -> [String: Any] {
        var body: [String: Any] = [
            "version": BrowserLinkContextCapture.contractVersion,
            "token": 1,
            "editable": isEditable,
        ]
        body["href"] = href ?? NSNull()
        body["imageURL"] = imageURL ?? NSNull()
        body["selectionText"] = selectionText ?? NSNull()
        return body
    }
}

/// A page that records the context-menu rows it is asked to run.
@MainActor
private final class RecordingContextMenuHost: BrowserPageContextMenuHost {
    private(set) var ran: [BrowserPageContextMenuAction] = []
    var performed: (BrowserPageContextMenuAction) -> Void = { _ in }

    func contextMenuActions(linkURL: URL?, selectionText: String?) -> [BrowserPageContextMenuAction] { [] }

    func performContextMenuAction(_ action: BrowserPageContextMenuAction) -> Bool {
        ran.append(action)
        performed(action)
        return true
    }
}
