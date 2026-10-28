import AppKit
import XCTest

@testable import Crest

@MainActor
final class BrowserAuthenticationWindowTests: XCTestCase {
    func testSystemSignInUsesTheRoutedWorkspaceWithAPrivateWindowOpenAndReleasesItsPageOnClose() throws {
        let application = try BrowserMacApplication()
        let host = WebKitShellHost()
        let windows = BrowserMacWindows(application: application, engineHost: host)
        let request = BrowserMacWindowRequest.normal(sourceWindowID: nil)
        windows.open(request, activation: .key)
        let owner = try XCTUnwrap(application.windowCoordinator.existingModel(for: request.id))
        let space = try XCTUnwrap(owner.browser.shownSpace)
        let tabs = space.tabs.models.map(\.id)
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        windows.openPrivateWindow()
        let destination = try application.browser.core.query(
            ExternalOpenDestination(windowIDs: [application.privatePages.windowID, request.id]))
        XCTAssertEqual(destination.spaceID, assignment.spaceID)
        let signInID = UUID()
        let existingPages = Set(application.browser.core.state.pages.keys)
        defer {
            windows.closeAuthenticationWindow(signInID)
            windows.window(for: application.privatePages.windowID)?.close()
            windows.window(for: request.id)?.close()
        }

        XCTAssertTrue(
            windows.openAuthenticationWindow(
                try XCTUnwrap(URL(string: "about:blank")), in: assignment, id: signInID,
                targetWindowID: destination.windowID))
        let newPages = application.browser.core.state.pages.filter { !existingPages.contains($0.key) }
        let page = try XCTUnwrap(newPages.values.first { $0.tabID == nil })
        XCTAssertEqual(page.spaceID, assignment.spaceID)
        XCTAssertEqual(page.workspaceID, owner.browser.window.workspaceID)
        XCTAssertNotEqual(page.workspaceID, application.privateBrowser.window.workspaceID)
        XCTAssertNil(application.browser.core.state.pages[page.id]?.tabID)
        XCTAssertEqual(space.tabs.models.map(\.id), tabs)

        windows.closeAuthenticationWindow(signInID)
        XCTAssertNil(application.browser.core.state.pages[page.id])
        XCTAssertEqual(space.tabs.models.map(\.id), tabs)
    }
}
