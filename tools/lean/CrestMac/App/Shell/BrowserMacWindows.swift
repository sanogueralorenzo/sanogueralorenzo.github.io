import AppKit
import SwiftUI

// MARK: - Types

/// The stores a focused browser window presents, which the menu bar's and the
/// engine's commands act on.
struct BrowserMacWindowContext {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let chrome: BrowserChromeState
    let windowID: UUID
}

extension EnvironmentValues {
    /// The shell's windows, which every window's content can open others
    /// through; nil outside a shell window.
    @Entry var browserMacWindows: BrowserMacWindows? = nil
}

/// Every window the shell opens, by kind and identity: it opens each one, or
/// brings forward the one already open under its identity, knows which one
/// the person is using, and lets go of what goes with each as it closes.
@MainActor
final class BrowserMacWindows {
    // MARK: - Types

    private struct AuthenticationWindow {
        let page: BrowserPage
        let browser: BrowserStore
        let pages: BrowserPagePool
        let chrome: BrowserChromeState
    }

    // MARK: - Variables

    private unowned let application: BrowserMacApplication
    private unowned let engineHost: any BrowserMacEngineHost

    /// The engine and version the build runs pages in, where it names one,
    /// as About Crest credits it.
    var engineCredits: String? { engineHost.aboutCredits }

    /// The windows open now, in the order they opened.
    private var controllers: [BrowserMacWindowController] = []
    private var authenticationWindows: [UUID: AuthenticationWindow] = [:]

    /// The window of the person's Spaces they are using: the key one, or the
    /// main one, or any.
    var activeBrowserWindow: NSWindow? {
        let browsing = controllers.filter(\.kind.hasWindowModel).map(\.window)
        if let key = NSApp.keyWindow, browsing.contains(where: { $0 === key }) { return key }
        return browsing.first { $0.isMainWindow } ?? browsing.first
    }

    /// The model of the key window, when it is a browser window over the
    /// person's own Spaces.
    var activeWindowModel: BrowserMacWindowModel? {
        guard let key = controller(showing: NSApp.keyWindow), key.kind.hasWindowModel else { return nil }
        return application.windowCoordinator.existingModel(for: key.windowID)
    }

    /// The stores of the key window, when it is a browser or the private window.
    var activeContext: BrowserMacWindowContext? {
        if controller(showing: NSApp.keyWindow)?.kind == .private {
            return BrowserMacWindowContext(
                browser: application.privateBrowser, pages: application.privatePages,
                chrome: application.privateChrome, windowID: application.privatePages.windowID)
        }
        return activeWindowModel.map(Self.context(of:))
    }

    /// The menu bar's commands as they run in the key browser window.
    var activeActions: BrowserCommandActions? {
        guard let context = activeContext else { return nil }
        return BrowserCommandActions(
            browser: context.browser, pages: context.pages, chrome: context.chrome, windows: self,
            targetWindowID: context.windowID)
    }

    var activeAuthenticationActions: BrowserCommandActions? {
        guard let controller = controller(showing: NSApp.keyWindow),
            let signIn = authenticationWindows[controller.windowID]
        else { return nil }
        return BrowserCommandActions(
            browser: signIn.browser, pages: signIn.pages, chrome: signIn.chrome, windows: self,
            authenticationPage: signIn.page)
    }

    var isAuthenticationWindowKey: Bool {
        controller(showing: NSApp.keyWindow)?.kind == .authentication
    }

    /// Whether the key window is one the shell opened, which the menu bar's
    /// close commands close even when it shows no browser.
    var isShellWindowKey: Bool {
        controller(showing: NSApp.keyWindow) != nil
    }

    var windowToBringForward: BrowserMacWindowController? {
        if let window = activeBrowserWindow, let controller = controller(showing: window) { return controller }
        return [BrowserMacWindowKind.private, .authentication, .browserImport].lazy.compactMap { kind in
            self.controllers.first { $0.kind == kind }
        }.first
    }

    // MARK: - Initializers

    init(application: BrowserMacApplication, engineHost: any BrowserMacEngineHost) {
        self.application = application
        self.engineHost = engineHost
        application.browser.core.followClosedTransientPages(self) { [weak self] closed in
            guard let self,
                let id = authenticationWindows.first(where: { $0.value.page.corePage.id == closed.pageID })?.key
            else { return }
            closeAuthenticationWindow(id)
        }
    }

    // MARK: - Actions - Lookup

    /// The window open under the core's identity `id`, or with none, the
    /// window an engine surface with no window of its own is shown in.
    func window(for id: UUID?) -> NSWindow? {
        guard let id else { return controllers.first(where: \.kind.hasWindowModel)?.window }
        return controllers.first { $0.windowID == id && $0.kind.identifier == nil }?.window
    }

    /// The identity of the browser window `window` is, over the person's own
    /// Spaces, or nil.
    func browserWindowID(of window: NSWindow) -> UUID? {
        controller(showing: window).flatMap { $0.kind.hasWindowModel ? $0.windowID : nil }
    }

    func pageRowWindowID(of window: NSWindow) -> UUID? {
        controller(showing: window).flatMap { $0.kind.hasPageRow ? $0.windowID : nil }
    }

    /// Whether a browser window is open under `id`.
    func isBrowserWindowOpen(_ id: UUID) -> Bool {
        controllers.contains { $0.kind.hasWindowModel && $0.windowID == id }
    }

    /// Whether `id` is the private window's identity while it is open.
    func isPrivateWindow(_ id: UUID) -> Bool {
        controllers.contains { $0.kind == .private && $0.windowID == id }
    }

    func contextBringingBrowserWindowForward() -> BrowserMacWindowContext? {
        if let context = activeContext { return context }
        let coordinator = application.windowCoordinator
        if let window = activeBrowserWindow, let controller = controller(showing: window),
            let model = coordinator.existingModel(for: controller.windowID)
        {
            controller.bringForward()
            return Self.context(of: model)
        }
        let request = BrowserMacWindowRequest.normal(sourceWindowID: nil)
        open(request, activation: .key)
        return coordinator.existingModel(for: request.id).map(Self.context(of:))
    }

    private static func context(of model: BrowserMacWindowModel) -> BrowserMacWindowContext {
        BrowserMacWindowContext(
            browser: model.browser, pages: model.pages, chrome: model.chrome, windowID: model.id)
    }

    private func controller(showing window: NSWindow?) -> BrowserMacWindowController? {
        guard let window else { return nil }
        return controllers.first { $0.window === window }
    }

    private func controller(_ kind: BrowserMacWindowKind, id: UUID? = nil) -> BrowserMacWindowController? {
        controllers.first { $0.kind == kind && (id == nil || $0.windowID == id) }
    }

    /// Whether a window of `kind` is open now.
    func isOpen(_ kind: BrowserMacWindowKind) -> Bool {
        controller(kind) != nil
    }

    /// Brings forward the window of `kind` already open, when one window of
    /// the kind is open at a time. Answers whether there was one.
    private func bringForwardOpenWindow(of kind: BrowserMacWindowKind) -> Bool {
        guard kind.isSingleton, let existing = controller(kind) else { return false }
        existing.present(.key)
        return true
    }

    // MARK: - Actions - Launch

    func openLaunchWindows(activation: BrowserMacWindowActivation = .key) {
        guard
            let plan = try? application.browser.core.query(LaunchWindows())
        else {
            open(.initial, activation: activation)
            return
        }
        open(plan, activation: activation)
    }

    /// Opens the launch's windows back to front, each coming forward without
    /// focus, and the frontmost last, as the key window.
    private func open(_ plan: LaunchWindowPlan, activation: BrowserMacWindowActivation = .key) {
        for id in plan.windowIDs {
            open(.reopening(id), activation: id == plan.startupWindowID ? activation : .background)
        }
    }

    // MARK: - Actions - Browser windows

    /// Opens the browser window `request` names, or brings forward the one
    /// open under its identity, as `activation` says.
    func open(_ request: BrowserMacWindowRequest, activation: BrowserMacWindowActivation) {
        let kind = BrowserMacWindowKind.browsing(request)
        if let existing = controllers.first(where: { $0.kind.hasWindowModel && $0.windowID == request.id }) {
            existing.present(activation)
            return
        }
        guard let model = application.windowCoordinator.model(for: request) else { return }
        show(
            kind, id: request.id, closeGate: model.closeGate,
            cascadingFrom: NSApp.keyWindow.flatMap { browserWindowID(of: $0) == nil ? nil : $0 },
            activation: activation, content: { _ in application.browserWindowContent(model) },
            closed: { [weak self] controller in
                self?.forget(controller)
                // The core forgets a window the person closed for the next
                // launch, and keeps the ones still open once a quit was allowed.
                self?.application.windowCoordinator.closeWindow(controller.windowID)
            })
    }

    // MARK: - Actions - Private window

    func openPrivateWindow() {
        guard !bringForwardOpenWindow(of: .private) else { return }
        let privatePages = application.privatePages
        application.pagePoolRegistry.register(
            privatePages, browser: application.privateBrowser, for: privatePages.windowID)
        show(
            .private, id: privatePages.windowID, closeGate: application.privateWindowCloseGate,
            content: { _ in application.privateWindowContent },
            closed: { [weak self] controller in self?.privateWindowClosed(controller) })
    }

    private func privateWindowClosed(_ controller: BrowserMacWindowController) {
        forget(controller)
        let profiles = application.privateBrowser.spaceModels.map(\.profileID)
        application.pagePoolRegistry.unregister(application.privatePages, for: controller.windowID)
        application.closePrivateBrowsingWindow()
        engineHost.windowClosed(controller.windowID, releasingProfiles: profiles)
    }

    // MARK: - Actions - Authentication

    /// Only the system authentication API opens these windows. Their page
    /// stays in the routed profile until the callback or the person closes it.
    func openAuthenticationWindow(
        _ url: URL, in assignment: BrowserSpaceRuntimeAssignment, id: UUID, targetWindowID: UUID?
    ) -> Bool {
        let owner = targetWindowID.flatMap { application.windowCoordinator.existingModel(for: $0) }
        let browser = owner?.browser ?? application.browser
        let pages = owner?.pages ?? application.pages
        guard let space = browser.spaceModel(matching: assignment),
            let page = pages.makeAuthenticationPage(url, in: space)
        else { return false }
        let chrome = BrowserChromeState(sidebarIsPresented: false)
        authenticationWindows[id] = AuthenticationWindow(
            page: page, browser: browser, pages: pages, chrome: chrome)
        BrowserNoticeCenter.shared.register(chrome) { [weak self] in
            self?.controller(.authentication, id: id)?.window.isKeyWindow == true
        }
        let gate = BrowserWindowCloseGate(core: browser.core) {
            PrepareToClosePages(requestID: UUID(), pageIDs: [page.corePage.id])
        }
        show(
            .authentication, id: id, closeGate: gate,
            content: { window in
                BrowserAuthenticationWindowContent(
                    page: page, browser: browser, pages: pages, chrome: chrome,
                    initialURL: url, window: window,
                    dismiss: { [weak self] in self?.closeAuthenticationWindow(id) })
            },
            closed: { [weak self] controller in
                guard let self else { return }
                forget(controller)
                authenticationWindows.removeValue(forKey: id)?.page.release(keepingState: false)
                engineHost.windowClosed(id, releasingProfiles: [])
            })
        return true
    }

    func closeAuthenticationWindow(_ id: UUID) {
        controller(.authentication, id: id)?.window.closeAfterApproval()
    }

    func closeAuthenticationWindows() {
        for id in Array(authenticationWindows.keys) { closeAuthenticationWindow(id) }
    }

    // MARK: - Actions - Import

    func openImportWindow(activation: BrowserMacWindowActivation = .key) {
        guard !bringForwardOpenWindow(of: .browserImport) else { return }
        let source = activeWindowModel
        show(
            .browserImport, activation: activation,
            content: { window in
                BrowserImportWindow(
                    browser: source?.browser ?? application.browser,
                    extensionInstaller: engineHost.importedExtensionInstaller,
                    closeWindow: { [weak window] in window?.close() })
            }, closed: { [weak self] controller in self?.forget(controller) })
    }

    // MARK: - Actions - Update details

    /// The software update details. One window,
    /// brought forward when asked again, and never restored at launch.
    func openSoftwareUpdateDetails() {
        guard !bringForwardOpenWindow(of: .updateDetails) else { return }
        show(
            .updateDetails,
            content: { window in
                BrowserSoftwareUpdateDetailsView(
                    model: application.softwareUpdates.model, closeWindow: { [weak window] in window?.close() }
                ).tint(CrestBrandTheme.accent)
            },
            closed: { [weak self] controller in self?.forget(controller) })
    }

    // MARK: - Actions - Presenting

    /// Opens a window of `kind` under `id` showing `content`, which opens
    /// other windows through these, places it cascading from `source` and
    /// brings it forward as `activation` says. `closed` says what goes with it.
    private func show<Content: View>(
        _ kind: BrowserMacWindowKind, id: UUID = UUID(), closeGate: BrowserWindowCloseGate? = nil,
        cascadingFrom source: NSWindow? = nil, activation: BrowserMacWindowActivation = .key,
        content: (BrowserMacWindow) -> Content, closed: @escaping @MainActor (BrowserMacWindowController) -> Void
    ) {
        let controller = BrowserMacWindowController(
            kind: kind, windowID: id, closeGate: closeGate,
            content: { window in content(window).environment(\.browserMacWindows, self) }, closed: closed)
        controllers.append(controller)
        controller.place(cascadingFrom: source)
        controller.present(activation)
    }

    // MARK: - Mutators

    private func forget(_ controller: BrowserMacWindowController) {
        controllers.removeAll { $0 === controller }
    }
}
