import AppKit

@main
enum LeanMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = LeanAppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
