import AppKit
import Carbon.HIToolbox
import Security
import ApplicationServices
@preconcurrency import UserNotifications
import WebKit

private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class BundleResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              url.scheme == "palette", url.host == "app" else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        let relativePath = String(url.path.drop(while: { $0 == "/" }))
        guard !relativePath.isEmpty, !relativePath.split(separator: "/").contains(".."),
              let resources = Bundle.main.resourceURL else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let fileURL = resources.appendingPathComponent("ui", isDirectory: true).appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mimeType: String
        switch fileURL.pathExtension.lowercased() {
        case "html": mimeType = "text/html"
        case "js": mimeType = "text/javascript"
        case "css": mimeType = "text/css"
        case "svg": mimeType = "image/svg+xml"
        case "png": mimeType = "image/png"
        default: mimeType = "application/octet-stream"
        }
        let response = URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

private final class RuntimeProbe {
    private let path: String?

    init(arguments: [String] = CommandLine.arguments) {
        guard let index = arguments.firstIndex(of: "--smoke-test-log"), arguments.indices.contains(index + 1) else {
            path = nil
            return
        }
        path = arguments[index + 1]
    }

    var isEnabled: Bool { path != nil }

    func record(_ event: String) {
        guard let path else { return }
        let previous = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        try? (previous + event + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
}

@main
@MainActor
final class PaletteAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    private enum LauncherView { case launcher, clipboard }

    private let shortcutID = EventHotKeyID(signature: 0x50414C54, id: 1) // PALT
    private let probe = RuntimeProbe()
    private var statusItem: NSStatusItem?
    private let resourceSchemeHandler = BundleResourceSchemeHandler()
    private var launcherPanel: LauncherPanel?
    private var webView: WKWebView?
    private var webViewLoaded = false
    private var pendingView: LauncherView = .launcher
    private var previousApplication: NSRunningApplication?
    private var shortcutRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var nodeService: NodeServiceProcess?
    private var clipboardTimer: Timer?
    private var clipboardChangeCount = NSPasteboard.general.changeCount
    private var captureError: String?
    private var capturePolicy: [String: Any]?
    private var appIcons: [String: String] = [:]
    private var clipboardShortcutRef: EventHotKeyRef?
    private var activationObserver: NSObjectProtocol?
    private var shortcutLabel = "⌥ Space"
    private var smokeStarted = false
    private var isReview: Bool { CommandLine.arguments.contains("--review") && CommandLine.arguments.contains("--data-dir") }

    static func main() {
        let application = NSApplication.shared
        let delegate = PaletteAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        probe.record("delegate-launched")
        installGlobalShortcut()
        configureStatusItem()
        startClipboardMonitor()
        if !CommandLine.arguments.contains("--background") {
            DispatchQueue.main.async { [weak self] in self?.showLauncher(view: CommandLine.arguments.contains("--clipboard") ? .clipboard : .launcher) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showLauncher() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        if let shortcutRef { UnregisterEventHotKey(shortcutRef) }
        if let clipboardShortcutRef { UnregisterEventHotKey(clipboardShortcutRef) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        clipboardTimer?.invalidate()
        nodeService?.stop()
    }

    @objc private func toggleLauncher() {
        if launcherPanel?.isVisible == true {
            dismissLauncher(restoreFocus: true)
        } else {
            showLauncher()
        }
    }

    @objc private func openClipboardHistory() {
        showLauncher(view: .clipboard)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "Palette")
            button.image?.isTemplate = true
            button.toolTip = "Palette"
        }

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open Palette", action: #selector(toggleLauncher), keyEquivalent: "")
        openItem.target = self
        openItem.keyEquivalentModifierMask = []
        openItem.representedObject = shortcutLabel
        openItem.toolTip = shortcutLabel
        menu.addItem(openItem)
        let clipboardItem = NSMenuItem(title: "Clipboard History", action: #selector(openClipboardHistory), keyEquivalent: "")
        clipboardItem.target = self
        clipboardItem.toolTip = "⌘⇧V"
        menu.addItem(clipboardItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
        probe.record("status-item-ready")
    }

    private func showLauncher(view: LauncherView = .launcher) {
        pendingView = view
        let panel = ensureLauncherPanel()
        resizePanel(view: view)
        position(panel)
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = frontmost
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        presentPendingView()
        probe.record("panel-shown")
    }

    private func dismissLauncher(restoreFocus: Bool) {
        guard let panel = launcherPanel, panel.isVisible else { return }
        webView?.evaluateJavaScript("window.dispatchEvent(new Event('paletteHidden'))")
        panel.orderOut(nil)
        if restoreFocus, let previousApplication, !previousApplication.isTerminated {
            previousApplication.activate(options: [])
        }
        previousApplication = nil
        probe.record("panel-hidden-resident")
    }

    private func ensureLauncherPanel() -> LauncherPanel {
        if let launcherPanel { return launcherPanel }

        let contentRect = NSRect(x: 0, y: 0, width: 680, height: 420)
        let panel = LauncherPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = true
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.animationBehavior = .utilityWindow

        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(self, name: "palette")
        configuration.setURLSchemeHandler(resourceSchemeHandler, forURLScheme: "palette")
        let webView = WKWebView(frame: contentRect, configuration: configuration)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]
        webView.wantsLayer = true
        webView.layer?.cornerRadius = 14
        webView.layer?.masksToBounds = true
        panel.contentView = webView

        self.launcherPanel = panel
        self.webView = webView
        loadInterface(in: webView)
        return panel
    }

    private func resizePanel(view: LauncherView) {
        guard let panel = launcherPanel else { return }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        let available = screen?.visibleFrame.size ?? NSSize(width: 1200, height: 800)
        let size = view == .clipboard ? NSSize(width: min(1040, available.width - 40), height: min(680, available.height - 40)) : NSSize(width: 680, height: 420)
        panel.setContentSize(size)
        position(panel)
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { panel.center(); return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: max(frame.minY + 12, min(frame.maxY - size.height - 12, frame.minY + frame.height * 0.56 - size.height / 2))
        )
        panel.setFrameOrigin(origin)
    }

    private func loadInterface(in webView: WKWebView) {
        if let uiURL = Self.uiURL() {
            probe.record("ui-resource-ready")
            _ = uiURL
            webView.load(URLRequest(url: URL(string: "palette://app/index.html")!))
        } else {
            probe.record("ui-resource-missing")
            webView.loadHTMLString(Self.fallbackHTML, baseURL: nil)
        }
    }

    private func presentPendingView() {
        guard webViewLoaded, let webView else { return }
        let script = pendingView == .clipboard ? "window.__paletteOpenClipboard?.()" : "window.__paletteOpen?.()"
        webView.evaluateJavaScript(script)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webViewLoaded = true
        presentPendingView()
        probe.record("webview-loaded")
        guard probe.isEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak webView] in
            webView?.evaluateJavaScript("typeof window.__paletteResolve === 'function' && document.querySelector('.palette-search') !== null") { result, _ in
                Task { @MainActor [weak self] in
                    guard let self, result as? Bool == true else {
                        self?.probe.record("webview-bridge-failed")
                        return
                    }
                    self.probe.record("webview-bridge-ready")
                    self.runSmokeTestIfNeeded()
                }
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dismissLauncher(restoreFocus: true)
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.launcherPanel?.isVisible == true, self.launcherPanel?.isKeyWindow == false else { return }
            self.dismissLauncher(restoreFocus: false)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "palette", let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "dismissLauncher" {
            dismissLauncher(restoreFocus: true)
            return
        }
        if type == "hostReady" {
            presentPendingView()
            probe.record("webview-bridge-ready")
            runSmokeTestIfNeeded()
            return
        }
        if type == "clearCaptureError" { captureError = nil; return }
        if type == "setView" {
            if body["view"] as? String == "clipboard", let captureError { reportCaptureError(captureError) }
            resizePanel(view: body["view"] as? String == "clipboard" ? .clipboard : .launcher)
            return
        }
        guard body["id"] is String else { return }
        if type == "copyClipboard" || type == "pasteClipboard" {
            restoreClipboard(body, paste: type == "pasteClipboard")
            return
        }
        service().send(body) { [weak self] response in
            guard let self else { return }
            var enriched = response
            if var payload = response["payload"] as? [String: Any] {
                if let policy = payload["policy"] as? [String: Any] { self.capturePolicy = policy }
                if let items = payload["items"] as? [[String: Any]] {
                    payload["items"] = items.map { item in
                        var result = item
                        if let id = item["sourceAppId"] as? String {
                            if let icon = self.appIcons[id] { result["sourceAppIcon"] = icon }
                            else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
                                    let data = ClipboardSupport.png(NSWorkspace.shared.icon(forFile: url.path), maximumEdge: 40) {
                                let icon = "data:image/png;base64," + data.base64EncodedString()
                                self.appIcons[id] = icon; result["sourceAppIcon"] = icon
                            }
                        }
                        return result
                    }
                }
                enriched["payload"] = payload
            }
            self.resolveInWebView(enriched)
        }
    }

    private func resolveInWebView(_ response: [String: Any]) {
        guard let webView else { return }
        Task {
            _ = try? await webView.callAsyncJavaScript(
                "window.__paletteResolve(response)",
                arguments: ["response": response],
                in: nil,
                contentWorld: .page
            )
        }
    }

    private func service() -> NodeServiceProcess {
        if let nodeService { return nodeService }
        let key = probe.isEnabled ? Data(repeating: 0x50, count: 32).base64EncodedString() : isReview ? Self.reviewStorageKey() : Self.clipboardStorageKey()
        let service = NodeServiceProcess(
            scriptURL: Self.nodeDaemonURL(),
            nodeURL: Self.nodeExecutableURL(),
            dataDirectory: Self.dataDirectoryURL(),
            indexerURL: Self.indexerURL(),
            clipboardKey: key,
            notificationHandler: Self.deliverNotification
        )
        self.nodeService = service
        if service.start() {
            probe.record("node-service-ready")
        } else {
            probe.record("node-service-failed")
        }
        return service
    }

    private func startClipboardMonitor() {
        clipboardChangeCount = NSPasteboard.general.changeCount
        service().send(["id": "initial-policy", "type": "getClipboardPolicy"]) { [weak self] response in
            self?.capturePolicy = (response["payload"] as? [String: Any])?["policy"] as? [String: Any]
        }
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.captureClipboardIfChanged() }
        }
        // Flush a pending copy before focus moves to another app.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let source = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.captureClipboardIfChanged(source: source) }
        }
    }

    private func captureClipboardIfChanged(source: NSRunningApplication? = nil) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != clipboardChangeCount else { return }
        clipboardChangeCount = pasteboard.changeCount
        guard let policy = capturePolicy, policy["enabled"] as? Bool == true else { return }
        let source = source ?? NSWorkspace.shared.frontmostApplication
        guard source?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        if let id = source?.bundleIdentifier, (policy["excludedAppIds"] as? [String] ?? []).contains(id) { return }
        let item: [String: Any]
        do {
            guard let captured = try ClipboardSupport.capture(pasteboard, source: source, ignoreSensitive: policy["ignoreSensitive"] as? Bool ?? true) else { return }
            item = captured
        } catch { reportCaptureError(error.localizedDescription); return }
        guard let id = item["id"] as? String else { return }
        service().send(["id": "capture-\(id)", "type": "captureClipboard", "item": item]) { [weak self] response in
            if response["ok"] as? Bool == false {
                self?.reportCaptureError(response["error"] as? String ?? "Clipboard capture failed")
            }
        }
    }

    private func reportCaptureError(_ message: String) {
        captureError = message
        webView?.callAsyncJavaScript("window.dispatchEvent(new CustomEvent('paletteCaptureError', {detail: message}))", arguments: ["message": message], in: nil, in: .page, completionHandler: nil)
    }

    private func restoreClipboard(_ request: [String: Any], paste: Bool) {
        guard let requestID = request["id"] as? String, let itemID = request["itemId"] as? String else { return }
        let target = previousApplication
        if paste {
            guard let target, !target.isTerminated else {
                resolveInWebView(["id": requestID, "ok": false, "error": "No previous app is available. Use Copy, then paste where you need it."])
                return
            }
            guard AXIsProcessTrusted() else {
                resolveInWebView(["id": requestID, "ok": false, "error": "Enable Palette in System Settings → Privacy & Security → Accessibility to paste directly. Copy works without this permission."])
                return
            }
        }
        service().send(["id": "restore-\(requestID)", "type": "getClipboardItem", "itemId": itemID]) { [weak self] response in
            guard let self else { return }
            guard response["ok"] as? Bool == true, let payload = response["payload"] as? [String: Any], let item = payload["item"] as? [String: Any] else {
                self.resolveInWebView(["id": requestID, "ok": false, "error": response["error"] as? String ?? "This clip is no longer available."])
                return
            }
            do {
                try ClipboardSupport.restore(item, to: .general)
                self.clipboardChangeCount = NSPasteboard.general.changeCount
                if paste, let target {
                    self.dismissLauncher(restoreFocus: true)
                    self.sendPaste(to: target, requestID: requestID, attempts: 10)
                } else {
                    self.resolveInWebView(["id": requestID, "ok": true, "payload": ["type": "copied", "copied": true]])
                }
            } catch { self.resolveInWebView(["id": requestID, "ok": false, "error": error.localizedDescription]) }
        }
    }

    private func sendPaste(to target: NSRunningApplication, requestID: String, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
                guard let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
                      let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
                    self.recoverPasteFailure(requestID: requestID, message: "Could not send the paste shortcut. The clip is copied; paste it manually.")
                    return
                }
                down.flags = .maskCommand; up.flags = .maskCommand
                down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
                self.resolveInWebView(["id": requestID, "ok": true, "payload": ["type": "copied", "copied": true]])
            } else if attempts > 0 { self.sendPaste(to: target, requestID: requestID, attempts: attempts - 1) }
            else {
                self.recoverPasteFailure(requestID: requestID, message: "Could not focus the previous app. The clip is copied; paste it manually.")
            }
        }
    }

    private func recoverPasteFailure(requestID: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        launcherPanel?.makeKeyAndOrderFront(nil)
        webView?.evaluateJavaScript("window.dispatchEvent(new Event('paletteShown'))")
        resolveInWebView(["id": requestID, "ok": false, "error": message])
    }

    private func runSmokeTestIfNeeded() {
        guard probe.isEnabled, !smokeStarted else { return }
        smokeStarted = true
        let originalWebView = webView
        let eventStatus = postRegisteredShortcutEvent()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            if eventStatus == noErr, self.launcherPanel?.isVisible == false {
                self.probe.record("global-shortcut-toggle-ready")
            }
            self.showLauncher()
            self.runStorageSmokeTest(originalWebView: originalWebView)
        }
    }

    private func runStorageSmokeTest(originalWebView: WKWebView?) {
        let sample = "palette-smoke-\(UUID().uuidString)"
        let item: [String: Any] = [
            "id": "smoke-item",
            "kind": "text",
            "content": sample,
            "createdAt": Int(Date().timeIntervalSince1970 * 1000),
            "pinned": false,
        ]
        service().send(["id": "smoke-capture", "type": "captureClipboard", "item": item]) { [weak self] response in
            guard let self else { return }
            if response["ok"] as? Bool == true { self.probe.record("clipboard-capture-ready") }
            self.service().send(["id": "smoke-list", "type": "listClipboard", "query": sample]) { [weak self] listResponse in
                guard let self else { return }
                if listResponse["ok"] as? Bool == true { self.probe.record("clipboard-retrieval-ready") }
                self.dismissLauncher(restoreFocus: false)
                self.showLauncher()
                if self.webView === originalWebView { self.probe.record("webview-reused") }
                self.dismissLauncher(restoreFocus: false)
                self.probe.record("SMOKE-COMPLETE")
                NSApp.terminate(nil)
            }
        }
    }

    private func postRegisteredShortcutEvent() -> OSStatus {
        var event: EventRef?
        let createStatus = CreateEvent(
            nil,
            OSType(kEventClassKeyboard),
            UInt32(kEventHotKeyPressed),
            GetCurrentEventTime(),
            EventAttributes(kEventAttributeNone),
            &event
        )
        guard createStatus == noErr, let event else { return createStatus }
        var hotKeyID = shortcutID
        let parameterStatus = SetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            MemoryLayout<EventHotKeyID>.size,
            &hotKeyID
        )
        guard parameterStatus == noErr else { return parameterStatus }
        return SendEventToEventTarget(event, GetApplicationEventTarget())
    }

    private func installGlobalShortcut() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var pressedID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &pressedID
            )
            guard status == noErr, [1, 2].contains(pressedID.id) else { return noErr }
            let delegate = Unmanaged<PaletteAppDelegate>.fromOpaque(userData).takeUnretainedValue()
            let isClipboard = pressedID.id == 2
            DispatchQueue.main.async { if isClipboard { delegate.openClipboardHistory() } else { delegate.toggleLauncher() } }
            return noErr
        }

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(), callback, 1, &eventType, userData, &eventHandlerRef
        )
        let configured = Self.configuredShortcut()
        shortcutLabel = configured.label
        let hotKeyID = shortcutID
        let shortcutStatus = RegisterEventHotKey(
            configured.keyCode, configured.modifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &shortcutRef
        )
        let clipboardStatus = RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey), EventHotKeyID(signature: 0x50414C54, id: 2), GetApplicationEventTarget(), 0, &clipboardShortcutRef)
        if clipboardStatus != noErr { NSLog("Palette: clipboard shortcut unavailable (%d); use the menu item", clipboardStatus) }
        if handlerStatus == noErr, shortcutStatus == noErr {
            probe.record("global-shortcut-ready")
        } else {
            NSLog("Palette: global shortcut unavailable (handler %d, shortcut %d)", handlerStatus, shortcutStatus)
            probe.record("global-shortcut-failed")
        }
    }

    private static func configuredShortcut() -> (keyCode: UInt32, modifiers: UInt32, label: String) {
        let argument: String? = {
            guard let index = CommandLine.arguments.firstIndex(of: "--hotkey"),
                  CommandLine.arguments.indices.contains(index + 1) else { return nil }
            return CommandLine.arguments[index + 1]
        }()
        let stored = UserDefaults.standard.string(forKey: "launcherShortcut")
        let raw = (argument ?? stored ?? ProcessInfo.processInfo.environment["PALETTE_HOTKEY"] ?? "option+space")
            .lowercased().replacingOccurrences(of: " ", with: "")
        switch raw {
        case "cmd+space", "command+space": return (UInt32(kVK_Space), UInt32(cmdKey), "⌘ Space")
        case "cmd+shift+space", "command+shift+space": return (UInt32(kVK_Space), UInt32(cmdKey | shiftKey), "⌘⇧ Space")
        case "ctrl+space", "control+space": return (UInt32(kVK_Space), UInt32(controlKey), "⌃ Space")
        case "ctrl+shift+space", "control+shift+space": return (UInt32(kVK_Space), UInt32(controlKey | shiftKey), "⌃⇧ Space")
        default: return (UInt32(kVK_Space), UInt32(optionKey), "⌥ Space")
        }
    }

    private static func uiURL() -> URL? {
        Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "ui")
    }

    private static func nodeDaemonURL() -> URL {
        if let configured = ProcessInfo.processInfo.environment["PALETTE_NODE_DAEMON"] {
            return URL(fileURLWithPath: configured)
        }
        return Bundle.main.url(forResource: "node-daemon", withExtension: "mjs", subdirectory: "node")
            ?? URL(fileURLWithPath: "dist/node/node-daemon.mjs")
    }

    private static func nodeExecutableURL() -> URL? {
        let fileManager = FileManager.default
        let candidates = [
            ProcessInfo.processInfo.environment["PALETTE_NODE_EXECUTABLE"],
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/node").path,
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
        ].compactMap { $0 }
        return candidates.first(where: fileManager.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }

    private static func indexerURL() -> URL? {
        if let configured = ProcessInfo.processInfo.environment["PALETTE_INDEXER"] {
            return URL(fileURLWithPath: configured)
        }
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/palette-indexer")
        return FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled : nil
    }

    private static func dataDirectoryURL() -> URL {
        if let index = CommandLine.arguments.firstIndex(of: "--data-dir"), CommandLine.arguments.indices.contains(index + 1) {
            return URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Palette", isDirectory: true)
    }

    private static func reviewStorageKey() -> String {
        let file = dataDirectoryURL().appendingPathComponent("review.key")
        if let data = try? Data(contentsOf: file), data.count == 32 { return data.base64EncodedString() }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return "" }
        do {
            try FileManager.default.createDirectory(at: dataDirectoryURL(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = Data(bytes)
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            return data.base64EncodedString()
        } catch { return "" }
    }

    fileprivate static func clipboardStorageKey() -> String {
        let service = "sh.palette.Desktop.clipboard"
        let account = "default"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data, data.count == 32 {
            return data.base64EncodedString()
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return "" }
        let data = Data(bytes)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { return "" }
        return data.base64EncodedString()
    }

    private static func deliverNotification(_ body: [String: Any]) {
        guard let notification = body["notification"] as? [String: Any],
              let title = notification["title"] as? String else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = notification["body"] as? String ?? ""
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            if granted { center.add(request) }
        }
    }

    private static let fallbackHTML = """
    <!doctype html><html><head><meta name="viewport" content="width=device-width"><style>
    :root{color-scheme:dark;font:17px -apple-system}body{margin:0;padding:16px;background:#18181b;color:#f5f5f7}
    input{box-sizing:border-box;width:100%;border:0;border-radius:10px;padding:14px;background:#29292e;color:inherit;font:inherit}
    p{color:#9b9ba3;font-size:13px}</style></head><body><input autofocus placeholder="Search apps, files, and commands">
    <p>Palette could not find its packaged interface. Rebuild the application bundle.</p></body></html>
    """
}

@MainActor
private final class NodeServiceProcess {
    private let scriptURL: URL
    private let nodeURL: URL?
    private let dataDirectory: URL
    private let indexerURL: URL?
    private let clipboardKey: String
    private let notificationHandler: ([String: Any]) -> Void
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var pending: [String: ([String: Any]) -> Void] = [:]
    private var buffer = Data()
    private let writer = DispatchQueue(label: "sh.palette.service-writer")

    init(
        scriptURL: URL,
        nodeURL: URL?,
        dataDirectory: URL,
        indexerURL: URL?,
        clipboardKey: String,
        notificationHandler: @escaping ([String: Any]) -> Void
    ) {
        self.scriptURL = scriptURL
        self.nodeURL = nodeURL
        self.dataDirectory = dataDirectory
        self.indexerURL = indexerURL
        self.clipboardKey = clipboardKey
        self.notificationHandler = notificationHandler
    }

    func start() -> Bool {
        if process?.isRunning == true { return true }
        guard !clipboardKey.isEmpty, let nodeURL, FileManager.default.fileExists(atPath: scriptURL.path) else { return false }
        let input = Pipe()
        let output = Pipe()
        let service = Process()
        service.executableURL = nodeURL
        service.arguments = scriptURL.pathExtension == "mjs"
            ? [scriptURL.path]
            : ["--experimental-strip-types", scriptURL.path]
        var environment = ProcessInfo.processInfo.environment
        if !clipboardKey.isEmpty { environment["PALETTE_CLIPBOARD_KEY"] = clipboardKey }
        environment["PALETTE_DATA_DIR"] = dataDirectory.path
        if let indexerURL { environment["PALETTE_INDEXER"] = indexerURL.path }
        service.environment = environment
        service.standardInput = input
        service.standardOutput = output
        service.standardError = FileHandle.standardError
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { self?.consume(data) }
        }
        service.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.didTerminate() }
        }
        do {
            try service.run()
            self.input = input
            self.output = output
            process = service
            return true
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            return false
        }
    }

    func stop() {
        output?.fileHandleForReading.readabilityHandler = nil
        if process?.isRunning == true { process?.terminate() }
        didTerminate()
    }

    func send(_ request: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        guard let id = request["id"] as? String,
              JSONSerialization.isValidJSONObject(request),
              start(), let input else {
            completion(["id": request["id"] as? String ?? "invalid", "ok": false, "error": "Palette service is unavailable"])
            return
        }
        pending[id] = completion
        writer.async { [weak self] in
            do {
                let data = try JSONSerialization.data(withJSONObject: request)
                try input.fileHandleForWriting.write(contentsOf: data + Data([0x0A]))
            } catch {
                DispatchQueue.main.async {
                    self?.pending.removeValue(forKey: id)?(["id": id, "ok": false, "error": "Palette service connection closed"])
                }
            }
        }
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard let response = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if response["type"] as? String == "notification" {
                notificationHandler(response)
                continue
            }
            guard let id = response["id"] as? String, let completion = pending.removeValue(forKey: id) else { continue }
            completion(response)
        }
    }

    private func didTerminate() {
        output?.fileHandleForReading.readabilityHandler = nil
        process = nil
        input = nil
        output = nil
        for (id, completion) in pending {
            completion(["id": id, "ok": false, "error": "Palette service stopped"])
        }
        pending.removeAll()
    }
}
