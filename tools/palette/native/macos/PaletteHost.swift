import AppKit
import Carbon.HIToolbox
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        installGlobalShortcut()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let shortcutRef {
            UnregisterEventHotKey(shortcutRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
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
        let openItem = NSMenuItem(title: "Open Palette", action: #selector(toggleLauncher), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Palette", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    private func makeLauncherWindow() -> NSWindow {
        let contentRect = NSRect(x: 0, y: 0, width: 680, height: 420)
        let window = NSPanel(
            contentRect: contentRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false,
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
        guard message.name == "palette", let body = message.body as? [String: Any], let requestID = body["id"] as? String else { return }
        // The native shell owns this transport boundary. A Node service
        // connection will forward requests and call the same resolver with a
        // typed response once the sidecar process is attached.
        let response: [String: Any] = ["id": requestID, "ok": false, "error": "Palette service is not attached"]
        guard JSONSerialization.isValidJSONObject(response), let data = try? JSONSerialization.data(withJSONObject: response), let json = String(data: data, encoding: .utf8) else { return }
        let script = "window.__paletteResolve(\(json))"
        launcherWindow?.contentView?.subviews.compactMap { $0 as? WKWebView }.first?.evaluateJavaScript(script)
    }

    private func installGlobalShortcut() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed),
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
                &pressedID,
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
            &eventHandlerRef,
        )

        // Option + Space is the safe default; shortcut configuration will move
        // into the shared settings service rather than this host shell.
        let hotKeyID = shortcutID
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &shortcutRef,
        )
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
