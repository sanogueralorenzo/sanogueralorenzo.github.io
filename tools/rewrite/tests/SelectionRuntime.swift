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
                if CommandLine.arguments.contains("--changed") {
                    print("Change the selected range now; checking in five seconds."); fflush(stdout)
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    guard captured.replacementLimitation() != nil else { throw RewriteError.message("FAIL changed selection was not rejected") }
                    print("PASS changed selection rejected")
                } else if CommandLine.arguments.contains("--copy-only") {
                    do {
                        try await captured.replace(with: Self.edited)
                        throw RewriteError.message("FAIL expected copy-only fallback")
                    } catch {
                        guard (Accessibility.value(captured.element, kAXSelectedTextAttribute) as? String) == Self.source,
                              Accessibility.fingerprint(captured.element) == captured.fingerprint,
                              error.localizedDescription.contains("Copy") else { throw error }
                        print("PASS unsupported replacement leaves original untouched and explains Copy")
                    }
                } else if CommandLine.arguments.contains("--replace") {
                    try await captured.replace(with: Self.edited)
                    guard let value = Accessibility.value(captured.element, kAXValueAttribute) as? String,
                          value == captured.fingerprint?.replacing(with: Self.edited) else { throw RewriteError.message("FAIL replacement verification") }
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == captured.app.processIdentifier else { throw RewriteError.message("FAIL source focus") }
                    print("PASS replacement and source focus")
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
