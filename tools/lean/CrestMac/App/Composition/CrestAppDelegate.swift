import AppKit

/// Crest over WebKit, which runs in AppKit's own process. The shared Mac shell
/// owns every window, the menu bar, launch, reopen, outside opens and quit;
/// this hands it AppKit's application hooks and the WebKit engine's small
/// part, which the shell's host asks for.
@MainActor
final class CrestAppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Variables

    private let shell = BrowserMacShell(engineHost: WebKitShellHost())

    // MARK: - Actions - Launch

    /// Starts the launch before AppKit hands over the links and documents a
    /// launch was asked to open, so they land in the windows it restores.
    func applicationWillFinishLaunching(_ notification: Notification) {
        shell.start { try BrowserMacApplication() }
    }

    /// AppKit restores no Crest window, so what it would keep is never read.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Actions - Application

    /// Holds the quit until the shell finishes it. Until the reply, AppKit
    /// runs the main run loop in its modal panel mode, which still drains the
    /// main queue and shows sheets: the core's wake, the pages' and the
    /// person's answers, the flush and the end of each turn all run there.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let isHeld = shell.requestQuit { allowed in sender.reply(toApplicationShouldTerminate: allowed) }
        return isHeld ? .terminateLater : .terminateNow
    }

    /// A Dock click or `Open` while Crest runs, which the shell answers in
    /// full; AppKit adds nothing of its own once it has.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        !shell.reopen()
    }

    /// Links and documents other apps hand Crest, which open where the core
    /// places them.
    func application(_ application: NSApplication, open urls: [URL]) {
        _ = shell.openExternal(urls)
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        shell.dockMenu()
    }
}
