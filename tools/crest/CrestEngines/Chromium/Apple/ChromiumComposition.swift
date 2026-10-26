#if CREST_CHROMIUM_HOST
    import AppKit
    import CrestCoreABI

    /// Crest's native application with a deferred Chromium runtime. Its shared
    /// Mac shell owns windows, menus, launch, outside opens and quit. Chromium
    /// starts its browser services and event pump when first needed and stays
    /// loaded until quit, attached to the application's existing core.
    @MainActor
    enum ChromiumComposition {
        // MARK: - Static Variables

        static let extensions = ChromiumExtensionStore()
        /// The shell Crest runs in, from the engine's start on.
        private(set) static var shell: BrowserMacShell?
        /// Chromium's Mac shell, for what only AppKit does.
        private(set) static var engineHost: (any CrestMacShell)?
        /// Chromium, the default engine, once the launch built the application.
        private(set) static var chromiumEngine: ChromiumEngine?
        private(set) static var runtime: ChromiumRuntime?
        private static var applicationDelegate: ChromiumApplicationDelegate?
        /// Where an earlier release listed the windows open at quit, before the
        /// core kept them.
        private static let legacyWindowListKey = "crest.chromium.windows.v1"

        // MARK: - Actions - Launch

        /// Starts Crest over the Mac shell's `host`, registering Chromium's C++
        /// `binding`, built against the engine contract `fingerprint` names,
        /// with the core; its pages reach the binding directly through `pages`.
        static func start(
            host: any CrestMacShell, binding: crest_engine_binding_t, fingerprint: [UInt8],
            pages: crest_engine_pages_t
        ) {
            if let runtime {
                engineHost = host
                runtime.bind(host: host, binding: binding, fingerprint: fingerprint, pages: pages)
                return
            }
            guard shell == nil else { return }
            // The Dock plug-in runs outside the browser process, including after
            // quit. App artwork uses the isolated app's domain, not an
            // environment-only browsing profile name that the Dock cannot find.
            BrowserMacDockTile.shared.defaults = .standard
            engineHost = host
            let shell = BrowserMacShell(engineHost: ChromiumShellHost(host: host))
            self.shell = shell
            // A recovery retry builds the engine and the application again.
            shell.start {
                let chromium = ChromiumEngine(host: host, table: binding, fingerprint: fingerprint, pages: pages)
                let application = try BrowserMacApplication(
                    defaultEngine: chromium,
                    // Site Controls is where a keyboard-triggered extension popup
                    // opens when the extension has no pinned tile to anchor to.
                    siteControlAnchor: BrowserSiteControlAnchor {
                        let anchor = BrowserExtensionPopupAnchorView()
                        anchor.site = .menu
                        return anchor
                    },
                    reviewPersistenceID: "chromium-native-ui-review")
                chromium.follow(application)
                chromiumEngine = chromium
                adoptLegacyWindowList(into: application)
                return application
            }
        }

        /// Starts AppKit without loading Chromium's framework. The launcher
        /// enters Chromium only after this loop exits for its first command.
        static func runNative() -> Int32 {
            UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true])
            let application = ChromiumApplication.shared
            let delegate = ChromiumApplicationDelegate()
            applicationDelegate = delegate
            application.delegate = delegate
            application.run()
            return runtime?.startRequested == true ? 1 : 0
        }

        static func startNative() {
            guard shell == nil else { return }
            BrowserMacDockTile.shared.defaults = .standard
            let runtime = ChromiumRuntime()
            self.runtime = runtime
            let shell = BrowserMacShell(engineHost: ChromiumRuntimeShell())
            self.shell = shell
            shell.start {
                let application = try BrowserMacApplication(
                    defaultEngine: runtime,
                    siteControlAnchor: BrowserSiteControlAnchor {
                        let anchor = BrowserExtensionPopupAnchorView()
                        anchor.site = .menu
                        return anchor
                    },
                    reviewPersistenceID: "chromium-native-ui-review")
                runtime.engine.follow(application)
                chromiumEngine = runtime.engine
                adoptLegacyWindowList(into: application)
                return application
            }
        }

        /// Hands the core the window list an earlier release kept in the
        /// launch's defaults, which the core carries once, then forgets the
        /// list. A list the core could not save stays for the next launch.
        private static func adoptLegacyWindowList(into application: BrowserMacApplication) {
            let environment = BrowserLaunchEnvironment.current
            let defaults: UserDefaults? =
                if !environment.requiresIsolation {
                    .standard
                } else if let isolationID = environment.persistentIsolationID {
                    UserDefaults(
                        suiteName: BrowserLaunchEnvironment.isolatedDefaultsSuiteName(isolationID: isolationID))
                } else {
                    nil
                }
            guard let stored = defaults?.array(forKey: legacyWindowListKey) as? [String] else { return }
            do {
                try application.browser.core.send(
                    AdoptOpenWindows(windowIDs: stored.compactMap(UUID.init(uuidString:))))
                defaults?.removeObject(forKey: legacyWindowListKey)
            } catch {
                DiagnosticLog.windows.notice(
                    "The core could not keep the windows an earlier release listed: \(DiagnosticLog.describe(error))")
            }
        }

        /// Asks the shell to quit; Chromium finishes an allowed quit itself
        /// once the pages are gone. False while the shell holds nothing.
        static func deferQuit() -> Bool {
            guard let shell, let engineHost else { return false }
            return shell.requestQuit { allowed in
                guard allowed else { return }
                engineHost.disposePages()
                engineHost.completeQuit()
            }
        }

        // MARK: - Actions - Extensions

        /// The engine let go of a profile, and its Space's extensions went with
        /// it. A private window's profile never derives from a Space's, so it
        /// is not affected.
        static func profileReleased(_ released: ProfileReleased) {
            extensions.refresh()
        }

        static var extensionSpaces: [BrowserSpaceIdentity] { shell?.application?.extensionSpaces ?? [] }

        /// The Space whose profile is `profileID`, when its extensions may act.
        static func extensionSpace(forProfile profileID: UUID) -> BrowserSpaceIdentity? {
            extensionSpaces.first { $0.profileID == profileID }
        }

        /// Whether this store is one of the persistent Spaces' own stores.
        ///
        /// Engine extension profiles belong to the application's persistent
        /// store family — every normal window's store shares it. A private
        /// window and a borrowed settings workspace each have a family of their
        /// own and no persistent engine profile, so neither may prepare or read
        /// one.
        static func ownsExtensionProfiles(_ browser: BrowserStore) -> Bool {
            guard let application = shell?.application else { return false }
            return browser.family === application.browser.family
                && !browser.isPrivateBrowsing && !browser.isTemporaryWorkspace
        }

        static func isSpaceLocked(_ space: BrowserSpaceIdentity) -> Bool {
            guard let application = shell?.application else { return true }
            return application.browser.deletingSpaceIDs.contains(space.id) || application.spaceAccess.isLocked(space)
        }

        /// The browser window the person is using, which an extension's popup
        /// or page opens against when nothing names one.
        static var activeNativeWindow: NSWindow? { shell?.windows?.activeBrowserWindow }

        /// Opens an extension's page as a tab of `space` in `window`. Settings
        /// and extension options are core-owned tabs even when no web page is
        /// active, so no opener is made up and no other Space is borrowed.
        static func openExtensionURL(_ url: URL, in space: BrowserSpaceIdentity, window: NSWindow) -> Bool {
            guard let application = shell?.application, let id = shell?.windows?.browserWindowID(of: window),
                let destination = URL(string: ChromiumInternalURL.presented(url.absoluteString))
            else { return false }
            return application.openTab(destination, in: space.assignment, window: id)
        }

        static func openExtensionSettings() {
            guard let application = shell?.application, let model = shell?.windows?.activeWindowModel,
                let space = model.browser.shownSpace, !application.spaceAccess.isLocked(space)
            else { return }
            application.openExtensionSettings(for: BrowserSpaceRuntimeAssignment(space: space), in: model.id)
        }

        /// The engine asked for a side-panel card: `chrome.sidePanel.open()`,
        /// `chrome.sidePanel.close()`, or an action click whose extension opens
        /// a panel instead of a popup. The card belongs to the page's own
        /// window's page row.
        static func routeSidePanel(_ requested: SidePanelRequested) {
            guard let shell, !shell.isQuitting, let page = chromiumEngine?.page(requested.pageID.uuidString),
                let window = page.surface.window
            else { return }
            guard let windowID = shell.windows?.pageRowWindowID(of: window),
                let host = BrowserExtensionSidePanelHosts.host(for: windowID)
            else {
                // A Quick Window or setup page has no card row to hold a panel,
                // and a panel belongs to its page, so say where it can open.
                if requested.request != .close {
                    showNativeNotice(
                        String(localized: "Side panels open in the main window. Open this page there to use it."),
                        icon: "sidebar.right")
                }
                return
            }
            BrowserExtensionSidePanelHost.route(
                requested.request, extensionID: requested.extensionID, page: page, host: host)
        }

        // MARK: - Actions - Notices

        /// Engine messages that ask nothing of the person — a toast, an action
        /// that could not run — are browser notices, never alerts.
        static func showNativeNotice(_ message: String, icon: String) {
            BrowserNoticeCenter.shared.post(
                BrowserNotice(
                    message: message,
                    systemImage: NSImage(systemSymbolName: icon, accessibilityDescription: nil) == nil
                        ? "info.circle" : icon))
        }

        /// A page asked to capture the screen in a way that needs Screen
        /// Recording access, which the system has not given Crest. The engine
        /// asked the system once and says so once per launch; the notice
        /// points at the setting rather than asking again.
        static func showScreenRecordingNotice() {
            BrowserNoticeCenter.shared.post(
                BrowserNotice(
                    message: String(localized: "Allow Crest in Screen & System Audio Recording to capture your screen"),
                    systemImage: "rectangle.dashed.badge.record",
                    action: BrowserNoticeAction(title: String(localized: "Open System Settings")) {
                        guard
                            let settings = URL(
                                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
                        else { return }
                        NSWorkspace.shared.open(settings)
                    }))
        }

        // MARK: - Actions - Translation

        /// Chromium's own translate bubble asks for whole-page translation,
        /// which Crest's translation toolbar answers, as Translate Page does.
        static func translatePage() {
            guard let shell, BrowserMacApplicationAction.translatePage.isEnabled(in: shell) else {
                showNativeNotice(String(localized: "This page can’t be translated."), icon: "globe")
                return
            }
            BrowserMacApplicationAction.translatePage.perform(in: shell)
        }

        static func translateText(_ text: String) {
            guard BrowserEngineRegistration.chromium.supports(.selectionTranslation) else { return }
            ChromiumSelectionTranslation.present(text)
        }
    }
#endif
