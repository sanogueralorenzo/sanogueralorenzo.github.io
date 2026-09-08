import AppKit
import CryptoKit

// An opt-in integration test of production selection code. It only accepts this
// exact disposable fixture, prepared in the destination app by the tester.
@main
@MainActor
final class SelectionRuntime: NSObject, NSApplicationDelegate {
    static let source = "She go to the library yesterday."
    static let edited = "She went to the library yesterday."
    static func main() {
        let app = NSApplication.shared, delegate = SelectionRuntime()
        app.delegate = delegate; app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
    static func clipboardDigest() -> [Data] {
        (NSPasteboard.general.pasteboardItems ?? []).flatMap { item in
            item.types.map { type in
                Data(SHA256.hash(data: Data(type.rawValue.utf8) + (item.data(forType: type) ?? Data())))
            }
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            do {
                let before = Self.clipboardDigest(), count = NSPasteboard.general.changeCount
                let args = CommandLine.arguments
                let appID = args.firstIndex(of: "--app").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
                let sourceApp = appID.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
                let captured = try CapturedSelection.capture(sourceApp: sourceApp)
                guard captured.text == Self.source else { throw RewriteError.message("Select only the documented disposable fixture before running this test.") }
                print("PASS capture: \(captured.app.localizedName ?? "app"); consistent range: \(captured.fingerprint != nil); direct replacement: \(captured.supportsReplacement)")
                if CommandLine.arguments.contains("--background") {
                    let window = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 300, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
                    window.title = "App-switch protection test"; window.isReleasedWhenClosed = false
                    NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
                    try await Task.sleep(nanoseconds: 250_000_000)
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier != captured.app.processIdentifier else {
                        throw RewriteError.message("FAIL test app did not become foreground")
                    }
                    do {
                        try await captured.replace(with: Self.edited, requireForeground: true)
                        throw RewriteError.message("FAIL background replacement was allowed")
                    } catch {
                        guard error.localizedDescription.contains("switched apps"), Accessibility.fingerprint(captured.element) == captured.fingerprint else { throw error }
                    }
                    window.orderOut(nil); captured.restoreFocus()
                    print("PASS app switch prevents automatic replacement without changing source")
                } else if CommandLine.arguments.contains("--changed") {
                    print("Change the selected range now; checking for up to 30 seconds."); fflush(stdout)
                    for _ in 0..<120 {
                        if captured.replacementLimitation() != nil { break }
                        try await Task.sleep(nanoseconds: 250_000_000)
                    }
                    guard captured.replacementLimitation() != nil else { throw RewriteError.message("FAIL changed selection was not rejected") }
                    do {
                        try await captured.replace(with: Self.edited, requireForeground: true)
                        throw RewriteError.message("FAIL stale selection was replaced")
                    } catch {
                        guard Accessibility.value(captured.element, kAXValueAttribute) as? String == captured.fingerprint?.value else { throw error }
                    }
                    print("PASS changed selection rejected without changing source")
                } else if CommandLine.arguments.contains("--unsupported") {
                    do {
                        try await captured.replace(with: Self.edited)
                        throw RewriteError.message("FAIL expected copy-only fallback")
                    } catch {
                        guard (Accessibility.value(captured.element, kAXSelectedTextAttribute) as? String) == Self.source,
                              Accessibility.fingerprint(captured.element) == captured.fingerprint,
                              error.localizedDescription.contains("replacement") else { throw error }
                        print("PASS unsupported replacement leaves original untouched and explains the limitation")
                    }
                } else if CommandLine.arguments.contains("--replace") || CommandLine.arguments.contains("--automatic") {
                    var edited = Self.edited
                    let automatic = CommandLine.arguments.contains("--automatic")
                    let status = MenuBarStatus(); defer { status.remove() }
                    if automatic {
                        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == captured.app.processIdentifier else {
                            throw RewriteError.message("Bring the disposable TextEdit document to the foreground before --automatic.")
                        }
                        status.setRewriting(.grammar)
                        let service = ProcessorService()
                        let models = try await service.models(for: .ollama)
                        guard let model = models.first else { throw RewriteError.message("No local Ollama model is available.") }
                        print("Rewriting the disposable fixture with Ollama; busy indicator is visible."); fflush(stdout)
                        edited = try await service.rewrite(Self.source, action: .grammar, configuration: ProcessorConfiguration(kind: .ollama, model: model))
                    }
                    try await captured.replace(with: edited, requireForeground: automatic)
                    status.setRewriting(nil)
                    guard let value = Accessibility.value(captured.element, kAXValueAttribute) as? String,
                          value == captured.fingerprint?.replacing(with: edited) else { throw RewriteError.message("FAIL replacement verification") }
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == captured.app.processIdentifier else { throw RewriteError.message("FAIL source focus") }
                    print("PASS \(automatic ? "automatic model result delivery" : "replacement") and source focus")
                }
                guard before == Self.clipboardDigest(), count == NSPasteboard.general.changeCount else { throw RewriteError.message("FAIL clipboard changed") }
                print("PASS clipboard bytes, types, item order, and change count preserved")
                NSApp.terminate(nil)
            } catch {
                print(error.localizedDescription); exit(1)
            }
        }
    }
}
