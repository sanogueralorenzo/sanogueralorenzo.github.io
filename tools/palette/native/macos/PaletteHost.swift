import AppKit
import Carbon.HIToolbox
import Security
import UserNotifications
import WebKit

/// Minimal macOS shell for Palette.
///
/// This file owns only macOS concerns: the status item, launcher window, and
/// global shortcut. Product commands and UI remain behind the WebView/IPC
/// boundary so the same contracts can be hosted by Windows and Linux later.
@main
final class PaletteAppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler {
    private let shortcutID = EventHotKeyID(signature: 0x50414C54, id: 1) // "PALT"
    private var statusItem: NSStatusItem?
    private var launcherWindow: NSWindow?
    private var shortcutRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var nodeService: NodeServiceProcess?
    private var clipboardTimer: Timer?
    private var clipboardChangeCount = NSPasteboard.general.changeCount
    private var lastCapturedClipboard = ""
    private var shortcutLabel = "⌥ Space"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        installGlobalShortcut()
        startClipboardMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let shortcutRef {
            UnregisterEventHotKey(shortcutRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        clipboardTimer?.invalidate()
        nodeService?.stop()
    }

    @objc private func toggleLauncher() {
        if let window = launcherWindow, window.isVisible {
            window.orderOut(nil)
            return
        }

        let window = makeLauncherWindow()
        launcherWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
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
        let openItem = NSMenuItem(title: "Open Palette  (\(shortcutLabel))", action: #selector(toggleLauncher), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        let clipboardItem = NSMenuItem(title: "Clipboard History  ⌘⇧V", action: #selector(openClipboardHistory), keyEquivalent: "")
        clipboardItem.target = self
        menu.addItem(clipboardItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Palette", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    @objc private func openClipboardHistory() {
        if launcherWindow == nil { launcherWindow = makeLauncherWindow() }
        NSApp.activate(ignoringOtherApps: true)
        launcherWindow?.makeKeyAndOrderFront(nil)
        launcherWindow?.contentView?.subviews.compactMap { $0 as? WKWebView }.first?.evaluateJavaScript("window.__paletteOpenClipboard?.()")
    }

    private func startClipboardMonitor() {
        // Seed the count so launching Palette never captures pre-existing data.
        clipboardChangeCount = NSPasteboard.general.changeCount
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            self?.captureClipboardIfChanged()
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
            "sensitive": false,
        ]
        if let sourceAppId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            item["sourceAppId"] = sourceAppId
        }
        guard JSONSerialization.isValidJSONObject(item) else { return }
        if nodeService == nil {
            nodeService = NodeServiceProcess(scriptURL: Self.nodeDaemonURL())
            nodeService?.start()
        }
        nodeService?.send(["id": "capture-\(itemID)", "type": "captureClipboard", "item": item]) { _ in }
    }

    private func makeLauncherWindow() -> NSWindow {
        let contentRect = NSRect(x: 0, y: 0, width: 680, height: 420)
        let window = NSPanel(
            contentRect: contentRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Palette"
        window.isReleasedWhenClosed = false
        window.center()

        let webView = WKWebView(frame: contentRect)
        webView.autoresizingMask = [.width, .height]
        webView.configuration.userContentController.add(self, name: "palette")
        if let uiURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "ui") {
            webView.loadFileURL(uiURL, allowingReadAccessTo: uiURL.deletingLastPathComponent())
        } else {
            webView.loadHTMLString(Self.fallbackHTML, baseURL: nil)
        }
        window.contentView = webView
        return window
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "palette", let body = message.body as? [String: Any], body["id"] is String else { return }
        if nodeService == nil {
            nodeService = NodeServiceProcess(scriptURL: Self.nodeDaemonURL())
            nodeService?.start()
        }
        nodeService?.send(body) { [weak self] response in
            guard let data = try? JSONSerialization.data(withJSONObject: response), let json = String(data: data, encoding: .utf8) else { return }
            let script = "window.__paletteResolve(\(json))"
            self?.launcherWindow?.contentView?.subviews.compactMap { $0 as? WKWebView }.first?.evaluateJavaScript(script)
        }
    }

    private static func nodeDaemonURL() -> URL {
        if let configured = ProcessInfo.processInfo.environment["PALETTE_NODE_DAEMON"] {
            return URL(fileURLWithPath: configured)
        }
        return Bundle.main.url(forResource: "node-daemon", withExtension: "mjs", subdirectory: "node")
            ?? Bundle.main.url(forResource: "node-daemon", withExtension: "ts")
            ?? URL(fileURLWithPath: "src/node-daemon.ts")
    }

    fileprivate static func clipboardStorageKey() -> String {
        let service = "com.palette.clipboard"
        let account = "default"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data, data.count == 32 {
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

    private func installGlobalShortcut() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var pressedID = EventHotKeyID()
            let size = MemoryLayout<EventHotKeyID>.size
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                size,
                nil,
                &pressedID
            )
            guard status == noErr, pressedID.id == 1 else { return noErr }
            let delegate = Unmanaged<PaletteAppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { delegate.toggleLauncher() }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )

        let configured = Self.configuredShortcut()
        shortcutLabel = configured.label
        let hotKeyID = shortcutID
        RegisterEventHotKey(
            configured.keyCode,
            configured.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &shortcutRef
        )
    }

    private static func configuredShortcut() -> (keyCode: UInt32, modifiers: UInt32, label: String) {
        let raw = ProcessInfo.processInfo.environment["PALETTE_HOTKEY"]?.lowercased().replacingOccurrences(of: " ", with: "")
        switch raw {
        case "cmd+space", "command+space": return (UInt32(kVK_Space), UInt32(cmdKey), "⌘ Space")
        case "cmd+shift+space", "command+shift+space": return (UInt32(kVK_Space), UInt32(cmdKey | shiftKey), "⌘⇧ Space")
        case "ctrl+space", "control+space": return (UInt32(kVK_Space), UInt32(controlKey), "⌃ Space")
        default: return (UInt32(kVK_Space), UInt32(optionKey), "⌥ Space")
        }
    }

    private static let fallbackHTML = """
    <!doctype html>
    <html><head><meta name=\"viewport\" content=\"width=device-width\"><style>
      :root { color-scheme: dark; font: -apple-system-body; }
      body { margin: 0; padding: 24px; background: #171719; color: #f5f5f7; }
      input { box-sizing: border-box; width: 100%; border: 0; outline: 0; border-radius: 10px;
        padding: 14px 16px; background: #29292d; color: inherit; font-size: 20px; }
      p { color: #96969d; margin: 18px 4px; }
    </style></head><body>
      <input autofocus placeholder=\"Search apps, files, and commands\">
      <p>Palette host is running. Connect the shared React UI and command service to this WebView.</p>
    </body></html>
    """
}

/// Small JSON-lines connection to the long-lived Node service.
    private final class NodeServiceProcess {
    private let scriptURL: URL
    private let input = Pipe()
    private let output = Pipe()
    private var process: Process?
    private var pending: [String: ([String: Any]) -> Void] = [:]
    private var buffer = Data()

    init(scriptURL: URL) {
        self.scriptURL = scriptURL
    }

    func stop() {
        output.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
    }

    func start() {
        guard process == nil else { return }
        let service = Process()
        service.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        let nodeArguments = scriptURL.pathExtension == "mjs"
            ? ["node", scriptURL.path]
            : ["node", "--experimental-strip-types", scriptURL.path]
        service.arguments = nodeArguments
        var environment = ProcessInfo.processInfo.environment
        let key = PaletteAppDelegate.clipboardStorageKey()
        if !key.isEmpty { environment["PALETTE_CLIPBOARD_KEY"] = key }
        if let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            environment["PALETTE_DATA_DIR"] = applicationSupport.appendingPathComponent("Palette", isDirectory: true).path
        }
        service.environment = environment
        service.standardInput = input
        service.standardOutput = output
        service.standardError = FileHandle.standardError
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }
        do {
            try service.run()
            process = service
        } catch {
            process = nil
        }
    }

    func send(_ request: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        guard let id = request["id"] as? String, JSONSerialization.isValidJSONObject(request), let data = try? JSONSerialization.data(withJSONObject: request) else { return }
        pending[id] = completion
        input.fileHandleForWriting.write(data)
        input.fileHandleForWriting.write(Data([0x0A]))
    }

    private func deliverNotification(_ body: [String: Any]) {
        guard let notification = body["notification"] as? [String: Any], let title = notification["title"] as? String else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = notification["body"] as? String ?? ""
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            center.add(request)
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
                DispatchQueue.main.async { self.deliverNotification(response) }
                continue
            }
            guard let id = response["id"] as? String, let completion = pending.removeValue(forKey: id) else { continue }
            DispatchQueue.main.async { completion(response) }
        }
    }
}
