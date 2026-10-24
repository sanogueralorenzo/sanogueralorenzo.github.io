import AppKit
import XCTest

@testable import Crest

@MainActor
final class BrowserBackgroundLaunchTests: XCTestCase {
    // MARK: - Actions - Background launch

    func testBackgroundLaunchLeavesTheExistingKeyWindowAndActivationUnchanged() throws {
        let application = try BrowserMacApplication()
        let host = WebKitShellHost()
        defer { withExtendedLifetime(host) {} }
        let windows = BrowserMacWindows(application: application, engineHost: host)
        let sentinel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        sentinel.isReleasedWhenClosed = false
        sentinel.makeKeyAndOrderFront(nil)
        // Only the active app holds a key window, and another app may be in
        // front while the tests run.
        guard sentinel.isKeyWindow else {
            sentinel.close()
            throw XCTSkip("The test host holds a key window only while it is the active app.")
        }
        let wasActive = NSApp.isActive
        let before = Set(NSApp.windows.map(\.windowNumber))
        defer {
            for window in NSApp.windows where !before.contains(window.windowNumber) { window.close() }
            sentinel.close()
        }
        windows.openLaunchWindows(activation: .background)
        XCTAssertTrue(NSApp.keyWindow === sentinel)
        XCTAssertEqual(NSApp.isActive, wasActive)
    }
}
