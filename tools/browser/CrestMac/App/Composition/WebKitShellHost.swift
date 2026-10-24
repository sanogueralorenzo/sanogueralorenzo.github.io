import AppKit
import WebKit

/// What Crest's Mac shell asks of WebKit, which needs nothing of it: WebKit's
/// pages live in Crest's own process and go with their windows, its key
/// equivalents reach Crest's menus through AppKit, and it has no extension
/// shortcuts or extensions an import could bring.
@MainActor
final class WebKitShellHost: BrowserMacEngineHost {
    // MARK: - Variables

    /// The system WebKit's version, which the build runs pages in.
    var aboutCredits: String? {
        (Bundle(for: WKWebView.self).infoDictionary?["CFBundleShortVersionString"] as? String).map { "WebKit \($0)" }
    }
    var importedExtensionInstaller: (any BrowserImportedExtensionInstalling)? { nil }

    // MARK: - Actions - Windows

    func windowClosed(_ windowID: UUID, releasingProfiles profileIDs: [UUID]) {}

    // MARK: - Actions - Shortcuts

    func handleUnclaimedShortcut(_ event: NSEvent, page: BrowserPage) -> Bool { false }
}
