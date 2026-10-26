#if CREST_CHROMIUM_HOST
    import AppKit

    /// What Crest's Mac shell asks of Chromium, through Chromium's Mac shell.
    @MainActor
    final class ChromiumShellHost: BrowserMacEngineHost {
        // MARK: - Variables

        private let host: any CrestMacShell

        var aboutCredits: String? { "Chromium \(host.engineVersion())" }
        var importedExtensionInstaller: (any BrowserImportedExtensionInstalling)? { ChromiumComposition.extensions }

        // MARK: - Initializers

        init(host: any CrestMacShell) {
            self.host = host
        }

        // MARK: - Actions - Windows

        func windowClosed(_ windowID: UUID, releasingProfiles profileIDs: [UUID]) {
            host.disposePages([], windows: [windowID], releaseProfiles: profileIDs)
        }

        // MARK: - Actions - Shortcuts

        /// Offers the chord to the extensions installed in the active page's
        /// own Space, as `chrome.commands` bindings.
        func handleUnclaimedShortcut(_ event: NSEvent, page: BrowserPage) -> Bool {
            guard let page = page.chromiumPage, let result = host.dispatchExtensionShortcut(event, page: page.pageID)
            else { return false }
            // An `_execute_action` binding runs through the core so the popup
            // keeps the anchor a click on the extension's own button would have
            // used: its pinned tile, or the control that opens the window's
            // extension list. A shortcut has no pointer location, so the pointer
            // is never the answer.
            if let extensionID = result.actionExtensionID {
                page.runExtension(
                    extensionID,
                    anchor: BrowserExtensionToolbarAnchorRegistry.anchor(for: extensionID, in: page.surface.window))
            }
            return true
        }
    }
#endif
