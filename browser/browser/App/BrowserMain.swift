import AppKit

@main
enum BrowserMain {
    @MainActor
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent == "browser" || arguments.first == "--cli" {
            BrowserCLI.run(arguments.first == "--cli" ? Array(arguments.dropFirst()) : arguments)
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = BrowserAppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
