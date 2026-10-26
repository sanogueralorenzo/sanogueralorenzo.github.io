import Foundation

/// Something a person asks of a Space's extensions: to open one of the
/// engine's own pages or the Chrome Web Store, or to change one extension.
/// Each command carries what it does, so the store runs any of them the same
/// way.
struct ExtensionCommand: Sendable {
    // MARK: - Static Variables

    /// The Chrome Web Store, at the extension's listing when one is named.
    static let store = ExtensionCommand(destination: { extensionID, _ in
        extensionID.isEmpty
            ? "https://chromewebstore.google.com/" : "https://chromewebstore.google.com/detail/\(extensionID)"
    })
    /// Chromium's extension manager.
    static let manage = ExtensionCommand(destination: { _, _ in "chrome://extensions/" })
    /// The keyboard shortcuts the engine binds to extensions.
    static let shortcuts = ExtensionCommand(destination: { _, _ in "chrome://extensions/shortcuts" })
    /// The extension's page in Chromium's extension manager.
    static let details = ExtensionCommand(destination: { extensionID, _ in "chrome://extensions/?id=\(extensionID)" })
    /// The extension's own settings page, when it has one.
    static let options = ExtensionCommand(destination: { _, options in options })
    static let enable = ExtensionCommand(change: .enable)
    static let disable = ExtensionCommand(change: .disable)
    static let remove = ExtensionCommand(change: .remove)
    static let pin = ExtensionCommand(change: .pin)
    static let unpin = ExtensionCommand(change: .unpin)

    // MARK: - Variables

    /// The address the command opens for the extension it names, given the
    /// settings page the extension's installed record names; nil when it
    /// opens nothing.
    let destination: @Sendable (_ extensionID: String, _ options: String?) -> String?
    /// The change the command makes to the extension, when it opens nothing.
    let change: ExtensionChange?

    // MARK: - Initializers

    private init(destination: @escaping @Sendable (_ extensionID: String, _ options: String?) -> String?) {
        self.destination = destination
        change = nil
    }

    private init(change: ExtensionChange) {
        destination = { _, _ in nil }
        self.change = change
    }
}
