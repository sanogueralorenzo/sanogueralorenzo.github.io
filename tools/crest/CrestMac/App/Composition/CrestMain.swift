import AppKit

/// The WebKit product's entry point, which runs AppKit's application with the
/// shared Mac shell behind `CrestAppDelegate`. The Chromium product is entered
/// through `ChromiumComposition` and leaves this folder out.
@main
enum CrestMain {
    // MARK: - Actions - Launch

    @MainActor
    static func main() {
        // The core decides which windows a launch opens. AppKit replays none
        // of the windows an earlier release saved for its own restoration.
        UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true])
        let application = NSApplication.shared
        let delegate = CrestAppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
