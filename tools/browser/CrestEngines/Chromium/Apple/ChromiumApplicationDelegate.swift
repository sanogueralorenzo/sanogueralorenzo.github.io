#if CREST_CHROMIUM_HOST
    import AppKit

    /// Owns AppKit launch and application hooks before and after an engine
    /// starts. Chromium supplies browser services and rendering, not this host.
    @MainActor
    final class ChromiumApplicationDelegate: NSObject, NSApplicationDelegate {
        // MARK: - Actions - Launch

        func applicationWillFinishLaunching(_ notification: Notification) {
            ChromiumComposition.startNative()
        }

        func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

        // MARK: - Actions - Application

        /// AppKit asks this for a quit Apple Event (the Dock's Quit, a logout,
        /// the updater's relaunch) and then calls `terminate`. Once Chromium
        /// runs it owns the process, and only `terminate` hands it the quit, so
        /// the shell's quit is left to that: holding it here would finish it
        /// with nobody to tell Chromium, and `terminate` would find it done.
        func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
            guard ChromiumComposition.engineHost == nil else { return .terminateNow }
            let held =
                ChromiumComposition.shell?.requestQuit { allowed in
                    sender.reply(toApplicationShouldTerminate: allowed)
                } ?? false
            return held ? .terminateLater : .terminateNow
        }

        func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
            !(ChromiumComposition.shell?.reopen() ?? false)
        }

        func application(_ application: NSApplication, open urls: [URL]) {
            _ = ChromiumComposition.shell?.openExternal(urls)
        }

        func applicationDockMenu(_ sender: NSApplication) -> NSMenu? { ChromiumComposition.shell?.dockMenu() }
    }
#endif
