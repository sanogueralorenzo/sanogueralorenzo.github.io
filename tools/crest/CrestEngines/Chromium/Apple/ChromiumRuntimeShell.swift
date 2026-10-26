#if CREST_CHROMIUM_HOST
    import AppKit

    /// The native shell never starts Chromium to answer a window or shortcut
    /// hook. Once its runtime is ready it forwards only the engine's own work.
    @MainActor
    final class ChromiumRuntimeShell: BrowserMacEngineHost {
        // MARK: - Variables

        var aboutCredits: String? { ChromiumComposition.engineHost.map { "Chromium \($0.engineVersion())" } }
        var importedExtensionInstaller: (any BrowserImportedExtensionInstalling)? { ChromiumComposition.extensions }

        // MARK: - Actions - Windows

        func windowClosed(_ windowID: UUID, releasingProfiles profileIDs: [UUID]) {
            ChromiumComposition.engineHost?.disposePages([], windows: [windowID], releaseProfiles: profileIDs)
        }

        // MARK: - Actions - Shortcuts

        func handleUnclaimedShortcut(_ event: NSEvent, page: BrowserPage) -> Bool {
            guard let host = ChromiumComposition.engineHost else { return false }
            return ChromiumShellHost(host: host).handleUnclaimedShortcut(event, page: page)
        }
    }
#endif
