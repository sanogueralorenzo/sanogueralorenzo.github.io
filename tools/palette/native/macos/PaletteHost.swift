import AppKit
import Carbon.HIToolbox
import Security
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
    private var lastCapturedClipboard = ""
    private var shortcutLabel = "⌥ Space"
    private var smokeStarted = false

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
            DispatchQueue.main.async { [weak self] in self?.showLauncher() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showLauncher() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        if let shortcutRef { UnregisterEventHotKey(shortcutRef) }
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
            button.image = NSImage(systemSymbolName: "command.circle", accessibilityDescription: "Palette")
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

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { panel.center(); return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + frame.height * 0.62 - size.height / 2
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
            probe.record("webview-bridge-ready")
            runSmokeTestIfNeeded()
            return
        }
        guard body["id"] is String else { return }
        service().send(body) { [weak self] response in
            self?.resolveInWebView(response)
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
        let service = NodeServiceProcess(
            scriptURL: Self.nodeDaemonURL(),
            nodeURL: Self.nodeExecutableURL(),
            dataDirectory: Self.dataDirectoryURL(),
            indexerURL: Self.indexerURL(),
            clipboardKey: probe.isEnabled
                ? Data(repeating: 0x50, count: 32).base64EncodedString()
                : Self.clipboardStorageKey(),
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
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.captureClipboardIfChanged() }
        }
    }

    private func captureClipboardIfChanged() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != clipboardChangeCount else { return }
        clipboardChangeCount = pasteboard.changeCount
        let fileURL = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL])?.first
        let content: String
        let kind: String
        if let fileURL, let path = fileURL.path, !path.isEmpty {
            content = path
            kind = "file"
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            content = text
            kind = text.contains("://") ? "url" : "text"
        } else {
            return
        }
        guard content != lastCapturedClipboard else { return }
        lastCapturedClipboard = content
        let itemID = UUID().uuidString
        var item: [String: Any] = [
            "id": itemID,
            "kind": kind,
            "content": content,
            "createdAt": Int(Date().timeIntervalSince1970 * 1000),
            "pinned": false,
        ]
        if let sourceAppID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            item["sourceAppId"] = sourceAppID
        }
        service().send(["id": "capture-\(itemID)", "type": "captureClipboard", "item": item]) { _ in }
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
            guard status == noErr, pressedID.id == 1 else { return noErr }
            let delegate = Unmanaged<PaletteAppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { delegate.toggleLauncher() }
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
        SecItemAdd(add as CFDictionary, nil)
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
        guard let nodeURL, FileManager.default.fileExists(atPath: scriptURL.path) else { return false }
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
              let data = try? JSONSerialization.data(withJSONObject: request),
              start(), let input else {
            completion(["id": request["id"] as? String ?? "invalid", "ok": false, "error": "Palette service is unavailable"])
            return
        }
        pending[id] = completion
        input.fileHandleForWriting.write(data)
        input.fileHandleForWriting.write(Data([0x0A]))
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
