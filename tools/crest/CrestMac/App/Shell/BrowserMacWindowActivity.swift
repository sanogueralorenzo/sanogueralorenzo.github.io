import AppKit
import Observation
import SwiftUI

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

    func end() {
        NotificationCenter.default.removeObserver(self)
        window = nil
    }

    @objc private func windowChanged() {
        refresh()
    }
}
