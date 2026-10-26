import AppKit

/// Crest's Mac application shell, which either engine's product runs: the
/// launch, or recovery when the session cannot open; the windows the core
/// restores; the menu bar; reopen and the Dock menu; links and documents from
/// other apps and system sign-in; the engine's own windows; and quit. The
/// engine that owns the process asks it through its entry points and answers
/// the little only it can through its `BrowserMacEngineHost`.
@MainActor
final class BrowserMacShell {
    // MARK: - Types

    /// What runs once the launch built the application.
    private struct Running {
        let application: BrowserMacApplication
        let windows: BrowserMacWindows
        let quit: BrowserMacQuit
        let menuBar: BrowserMacMenuBar
        let dockMenu: BrowserMacDockMenu
        let externalOpening: BrowserMacExternalOpening
        let agents: BrowserMacAgents
    }

    /// A system sign-in that arrived before the launch finished.
    private struct PendingSignIn {
        let url: URL
        let windowID: UUID
        let declined: @MainActor () -> Void
    }

    // MARK: - Variables

    let engineHost: any BrowserMacEngineHost
    private var launch: BrowserApplicationLaunch<BrowserMacApplication>?
    private var recovery: BrowserMacLaunchRecovery?
    private var running: Running?
    /// Links and documents other apps handed over before the launch finished,
    /// which can be while recovery is on screen; they open once it has.
    private var pendingOpens: [URL] = []
    private var pendingSignIns: [PendingSignIn] = []
    /// Offers every key down to `handleShortcut` before any view sees it.
    /// Both engines' page views take key equivalents before the menu bar
    /// does, so this is where Crest's shortcuts go ahead of a page when the
    /// core reserves them from pages, and ahead of Crest's own views always.
    private var keyMonitor: Any?
    /// Takes a mouse's Back and Forward clicks whole in every window, ahead of
    /// any view.
    private let mouseButtons = BrowserMacMouseButtons()
    /// The recent tabs a held Most Recent Tab shortcut shows.
    let recentTabSwitcher = BrowserMacRecentTabSwitcher()

    /// The application, once the launch built it.
    var application: BrowserMacApplication? { running?.application }
    /// The windows, once the launch built the application.
    var windows: BrowserMacWindows? { running?.windows }
    /// Whether a quit is being prepared or finished, so nothing new opens.
    var isQuitting: Bool { running?.quit.isQuitting ?? false }

    // MARK: - Initializers

    init(engineHost: any BrowserMacEngineHost) {
        self.engineHost = engineHost
    }

    // MARK: - Actions - Launch

    /// Builds the application with `factory` and opens what the core says the
    /// launch opens, or shows recovery when the session cannot open and
    /// continues from there once it can. A retry runs `factory` again.
    func start(launching factory: @escaping @MainActor () throws -> BrowserMacApplication) {
        guard launch == nil else { return }
        let launch = BrowserApplicationLaunch(factory)
        self.launch = launch
        if let application = launch.value {
            run(application)
        } else {
            recovery = BrowserMacLaunchRecovery(launch: launch) { [weak self] in self?.run($0) }
        }
    }

    /// Runs the application the launch built. A test host builds it and
    /// shows nothing: no window, menu, Dock tile or sync of its own.
    private func run(_ application: BrowserMacApplication) {
        guard running == nil else { return }
        let windows = BrowserMacWindows(application: application, engineHost: engineHost)
        let menuBar = BrowserMacMenuBar(
            shell: self, shortcuts: application.shortcuts, state: application.browser.core.state)
        running = Running(
            application: application, windows: windows,
            quit: BrowserMacQuit(application: application, windows: windows), menuBar: menuBar,
            dockMenu: BrowserMacDockMenu(application: application, windows: windows),
            externalOpening: BrowserMacExternalOpening(application: application, windows: windows),
            agents: BrowserMacAgents(application: application, windows: windows))
        recovery?.close()
        recovery = nil
        guard application.presentsInstalledApplicationUI else { return }
        BrowserMacAppearance.shared.start()
        BrowserMacDockTile.shared.start(following: application.browser.core)
        let background = application.launchesInBackground
        windows.openLaunchWindows(activation: background ? .background : .key)
        menuBar.install()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let pageSeesFirst = BrowserWebHostView.isPageContent(NSApp.keyWindow?.firstResponder)
            return self?.handleShortcut(event, pageSeesFirst: pageSeesFirst) == true ? nil : event
        }
        mouseButtons.start()
        recentTabSwitcher.start(in: self)
        running?.agents.start()
        Task { await application.cloudSync.start() }
        if !background { NSApp.activate(ignoringOtherApps: true) }
        openPending()
    }

    private func openPending() {
        let opens = pendingOpens
        let signIns = pendingSignIns
        pendingOpens = []
        pendingSignIns = []
        if !opens.isEmpty { _ = openExternal(opens) }
        for signIn in signIns {
            _ = openAuthenticationSession(signIn.url, window: signIn.windowID, declined: signIn.declined)
        }
    }

    // MARK: - Actions - Application

    /// A quit the application was asked for, which `finish` completes once the
    /// core allowed it and every edit is saved, or with false when it did not.
    /// Answers false when there is nothing to hold, before the launch finished
    /// or once the quit was finished, so the entry point quits at once.
    func requestQuit(finish: @escaping @MainActor (_ allowed: Bool) -> Void) -> Bool {
        guard let running else { return false }
        return running.quit.request { allowed in
            // No agent reaches a Crest that is going.
            if allowed { running.agents.stop() }
            finish(allowed)
        }
    }

    /// A Dock click or `Open` with no Crest window. An open window comes
    /// forward; with none, setup does while it holds the launch back, and
    /// otherwise the window the core names opens. Answers false when the shell
    /// is not running or is quitting.
    func reopen() -> Bool {
        guard let running, !running.quit.isQuitting else { return false }
        let application = running.application
        if let window = running.windows.windowToBringForward {
            window.bringForward()
        } else if let setup = try? application.browser.core.query(
            LaunchSetup(environment: application.launchEnvironment)
        ).setup {
            running.windows.openOnboardingWindow(BrowserOnboardingRequest(entryPoint: setup))
        } else if let reopened = try? application.browser.core.query(
            WindowToReopen(windowIDs: application.stackedWindowIDs))
        {
            running.windows.open(.reopening(reopened.windowID), activation: .key)
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    /// The Dock icon's menu: Crest's window commands and Spaces, ahead of the
    /// window list and the items macOS adds itself.
    func dockMenu() -> NSMenu? {
        guard let running, !running.quit.isQuitting else { return nil }
        return running.dockMenu.menu()
    }

    // MARK: - Actions - External opens

    /// Links and documents from other apps, opened where the core places them
    /// once the launch finished. Answers whether Crest takes them, which it
    /// does for every one it accepts.
    func openExternal(_ urls: [URL]) -> Bool {
        let accepted = urls.filter {
            $0.isFileURL ? ExternalLocalDocument.accepts($0) : ExternalWebLink.accepts($0)
        }
        guard !accepted.isEmpty else { return true }
        guard let running else {
            pendingOpens.append(contentsOf: accepted)
            return true
        }
        Task { @MainActor in await running.externalOpening.open(accepted) }
        return true
    }

    // MARK: - Actions - System sign-in

    /// An app's `ASWebAuthenticationSession` sign-in. It lands in the Space a
    /// link from that app routes to, always as a Quick Window named
    /// `windowID`: the session is transient and the engine closes the window
    /// when the page reaches the app's callback. `declined` runs when the core
    /// places it nowhere, so the app learns at once. Answers whether Crest
    /// takes it.
    func openAuthenticationSession(
        _ url: URL, window windowID: UUID, declined: @escaping @MainActor () -> Void
    ) -> Bool {
        guard ExternalWebLink.accepts(url) else { return false }
        guard let running else {
            pendingSignIns.append(PendingSignIn(url: url, windowID: windowID, declined: declined))
            return true
        }
        Task { @MainActor in
            guard let destination = await running.externalOpening.destination(for: url) else {
                declined()
                return
            }
            running.windows.openQuickWindow(
                BrowserQuickWindowRequest(
                    id: windowID, url: url, spaceAssignment: destination.assignment,
                    targetWindowID: destination.quickWindowTarget))
            guard let window = running.windows.quickWindow(windowID) else {
                declined()
                return
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    /// The sign-in in the Quick Window `windowID` is over; a before-unload
    /// prompt would only get in the way.
    func closeAuthenticationSession(_ windowID: UUID) {
        running?.windows.closeQuickWindowWithoutAsking(windowID)
    }

    // MARK: - Actions - Engine windows

    /// The window open under the core's identity `id`, or with none, the
    /// window an engine surface with no window of its own is shown in.
    func window(for id: UUID?) -> NSWindow? {
        running?.windows.window(for: id)
    }

    /// Reserves the Crest window that will host a browser the engine created
    /// for itself and names the Space its tabs belong to, as the core places
    /// them over the windows as AppKit stacks them.
    ///
    /// Crest is one window. The browser's tabs join the window the person is
    /// using, and only one an extension asked for by name (`ownWindow`) opens
    /// another. Nothing is presented here: the engine creates the browser
    /// first and offers its tabs afterwards. The core declines a profile with
    /// no Space to host it, so the engine drops those tabs rather than routing
    /// them into an unrelated Space, an off-the-record profile once the
    /// private window is closed, and a Space that is locked or being deleted.
    func reserveEngineWindow(forProfile profileID: UUID, ownWindow: Bool) -> (window: UUID, space: UUID)? {
        guard let running, !running.quit.isQuitting else { return nil }
        let application = running.application
        guard
            let place = try? application.browser.core.query(
                EngineWindowPlacement(
                    profileID: profileID, ownWindow: ownWindow, windowIDs: application.stackedWindowIDs)),
            let window = place.windowID, let space = place.spaceID
        else { return nil }
        return (window, space)
    }

    /// Opens the window reserved for an engine-created browser, just before
    /// its first tab is offered for adoption, coming forward as `focused`
    /// says.
    func presentEngineWindow(_ windowID: UUID, space spaceID: UUID, focused: Bool) {
        guard let running, !running.quit.isQuitting else { return }
        let windows = running.windows
        if windows.isPrivateWindow(windowID) {
            if focused { windows.window(for: windowID)?.makeKeyAndOrderFront(nil) }
            return
        }
        windows.open(BrowserMacWindowRequest(id: windowID, kind: .normal), activation: focused ? .key : .background)
        guard windows.isBrowserWindowOpen(windowID) else { return }
        running.application.selectSpace(spaceID, in: windowID)
        if focused { NSApp.activate(ignoringOtherApps: true) }
    }
}
