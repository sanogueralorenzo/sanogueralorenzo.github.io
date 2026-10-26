import AppKit
import Observation
import SwiftUI

/// How active one shell window is, which its SwiftUI content reads as its
/// scene phase. A view an `NSHostingController` hosts belongs to no SwiftUI
/// scene, so nothing else would tell it; what the phase drives, such as
/// retention sweeps, flushing the window's edits, pausing its sidebar widgets
/// and its Quick Window and Peek pages, would never follow the window.
///
/// The phase follows SwiftUI's own on the Mac: a window on screen is active
/// whether or not it is key and whether or not the app is, and one that is
/// minimized or hidden with the app is in the background.
@Observable
@MainActor
final class BrowserMacWindowActivity: NSObject {
    // MARK: - Types

    /// Puts the window's phase in its content's environment.
    struct Phase: ViewModifier {
        let activity: BrowserMacWindowActivity

        func body(content: Content) -> some View {
            content.environment(\.scenePhase, activity.phase)
        }
    }

    // MARK: - Variables

    /// The window's phase now.
    private(set) var phase: ScenePhase = .active
    @ObservationIgnored private weak var window: NSWindow?

    // MARK: - Initializers

    /// Follows `window`, which is taken to come on screen as it opens.
    init(following window: NSWindow) {
        self.window = window
        super.init()
        let center = NotificationCenter.default
        for name in [
            NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
            NSWindow.didChangeOcclusionStateNotification,
        ] {
            center.addObserver(self, selector: #selector(windowChanged), name: name, object: window)
        }
        for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            center.addObserver(self, selector: #selector(windowChanged), name: name, object: NSApp)
        }
    }

    // MARK: - Actions - Phase

    /// Reads the window's phase again, once it came forward or went.
    func refresh() {
        let next: ScenePhase =
            if let window, window.isVisible, !window.isMiniaturized, !NSApp.isHidden { .active } else { .background }
        if next != phase { phase = next }
    }

    /// The window closed, and its content goes with it: the phase stays as
    /// it was, so nothing its content does on leaving the foreground, such as
    /// a Quick Window locking every Space, runs for a window that is going.
    func end() {
        NotificationCenter.default.removeObserver(self)
        window = nil
    }

    @objc private func windowChanged() {
        refresh()
    }
}
