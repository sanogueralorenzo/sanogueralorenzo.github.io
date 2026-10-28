import AppKit
import SwiftUI

/// The window a launch that could not open the session shows instead of the
/// browser, with a menu bar that can only quit. Restoring the session there
/// continues into the normal launch.
@MainActor
final class BrowserMacLaunchRecovery {
    // MARK: - Types

    /// The recovery view, which hands the application on once the launch
    /// built it.
    private struct Content: View {
        let launch: BrowserApplicationLaunch<BrowserMacApplication>
        let launched: @MainActor (BrowserMacApplication) -> Void

        var body: some View {
            BrowserSessionRecoveryView(launch: launch)
                .onChange(of: launch.value != nil, initial: true) {
                    if let application = launch.value { launched(application) }
                }
        }
    }

    // MARK: - Variables

    private let window: NSWindow
    /// Quits on Command-Q even while the engine's own views would take the
    /// key equivalent first.
    private var keyMonitor: Any?

    // MARK: - Initializers

    /// Shows recovery for `launch`, and calls `launched` once it succeeds.
    init(
        launch: BrowserApplicationLaunch<BrowserMacApplication>,
        launched: @escaping @MainActor (BrowserMacApplication) -> Void
    ) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 380),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = String(localized: "Crest Recovery")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentView = NSHostingView(rootView: Content(launch: launch, launched: launched))
        let menu = NSMenu()
        let item = NSMenuItem()
        let applicationMenu = NSMenu(title: ProductIdentity.name)
        let quit = NSMenuItem(
            title: String(localized: "Quit Crest"), action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        quit.target = NSApp
        applicationMenu.addItem(quit)
        item.submenu = applicationMenu
        menu.addItem(item)
        NSApp.mainMenu = menu
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                event.charactersIgnoringModifiers == "q"
            else { return event }
            NSApp.terminate(nil)
            return nil
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Actions - Closing

    /// The launch succeeded: recovery goes, and the shell's menus replace its
    /// own.
    func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        window.close()
    }
}
