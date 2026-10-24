import AppKit
import SwiftUI

/// One window the shell opened: its AppKit window and the SwiftUI content it
/// hosts, where it is placed and the frame it keeps, how active it is, and
/// what goes when it closes.
@MainActor
final class BrowserMacWindowController: NSObject {
    // MARK: - Static Variables

    /// What a window keeps its frame under, after its identity.
    private static let frameNamePrefix = "crest.window."
    /// What the Chromium product's windows kept their frames under before
    /// both products shared one shell.
    private static let legacyFrameNamePrefix = "crest.chromium.window."

    // MARK: - Variables

    let kind: BrowserMacWindowKind
    /// The window's identity: the core's for a browser, private or Quick
    /// Window, and one of its own for any other.
    let windowID: UUID
    let window: BrowserMacWindow
    private let activity: BrowserMacWindowActivity
    /// What goes with the window when it closes, which the window's opener
    /// decided.
    private let closed: @MainActor (BrowserMacWindowController) -> Void

    // MARK: - Initializers

    /// A window of `kind` showing the content `content` makes for it, which
    /// asks `closeGate` whether it may close when the person asks and runs
    /// `closed` once it did.
    init<Content: View>(
        kind: BrowserMacWindowKind, windowID: UUID = UUID(), closeGate: BrowserWindowCloseGate? = nil,
        content: (BrowserMacWindow) -> Content, closed: @escaping @MainActor (BrowserMacWindowController) -> Void
    ) {
        self.kind = kind
        self.windowID = windowID
        self.closed = closed
        window = kind.makeWindow(identifiedBy: windowID)
        window.closeGate = closeGate
        activity = BrowserMacWindowActivity(following: window)
        super.init()
        kind.host(
            content(window)
                .modifier(BrowserMacWindowActivity.Phase(activity: activity))
                .modifier(BrowserDeviceAppearanceEnvironment()),
            in: window)
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose), name: NSWindow.willCloseNotification, object: window)
    }

    // MARK: - Actions - Presenting

    /// Places the window: at the frame it kept, or cascaded from `source`, the
    /// window the person is using, at that window's size, as new windows open
    /// on the Mac. A window of a kind that fills the screen takes the visible
    /// frame of the screen the person is using; one of a kind that keeps no
    /// frame, or with no source, opens centered.
    func place(cascadingFrom source: NSWindow?) {
        guard kind.savesFrame else {
            if kind.fillsScreen, let screen = source?.screen ?? NSScreen.main {
                window.setFrame(screen.visibleFrame, display: false)
            } else {
                window.center()
            }
            return
        }
        if restoreFrame() { return }
        guard let source, source !== window, !source.styleMask.contains(.fullScreen) else {
            window.center()
            return
        }
        window.setFrame(source.frame, display: false)
        let sourceTopLeft = NSPoint(x: source.frame.minX, y: source.frame.maxY)
        window.cascadeTopLeft(from: window.cascadeTopLeft(from: sourceTopLeft))
    }

    /// Brings the window forward as `activation` says, restoring it when it
    /// was minimized.
    func present(_ activation: BrowserMacWindowActivation) {
        activation.present(window)
        activity.refresh()
    }

    /// Brings the window forward as the key window, restoring it when it was
    /// minimized.
    func bringForward() {
        if window.isMiniaturized { window.deminiaturize(nil) }
        present(.key)
    }

    // MARK: - Actions - Frame

    /// Places the window at the frame it keeps under its identity, or the one
    /// it kept under the Chromium product's earlier name, which it now keeps
    /// under its own. Answers whether it had one.
    private func restoreFrame() -> Bool {
        let name = Self.frameNamePrefix + windowID.uuidString
        let legacyName = Self.legacyFrameNamePrefix + windowID.uuidString
        let restored = window.setFrameUsingName(name) || window.setFrameUsingName(legacyName)
        NSWindow.removeFrame(usingName: legacyName)
        window.setFrameAutosaveName(name)
        return restored
    }

    // MARK: - Actions - Closing

    @objc private func windowWillClose() {
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
        activity.end()
        closed(self)
        // AppKit keeps the frame the window last saved. The name goes with the
        // window, since AppKit gives it to no other window while this one is
        // alive, so the window reopened under this identity keeps saving.
        if kind.savesFrame { window.setFrameAutosaveName("") }
        // The content lets go of the window's runtime when it hears the close
        // too, which can be after this, so it goes on the next turn.
        Task { @MainActor [window] in window.contentViewController = nil }
    }
}
