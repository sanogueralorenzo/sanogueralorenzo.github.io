#if CREST_CHROMIUM_HOST
    import Foundation

    /// Where a side panel request an extension made for one page's own tab
    /// goes. The engine has already checked that the extension has an entry
    /// for the tab, so the only remaining decision is what the tab is showing:
    /// a second request for the panel already there toggles or is ignored
    /// rather than rebuilding the same document.
    @MainActor
    struct ChromiumSidePanelRoute {
        // MARK: - Variables

        let extensionID: String
        let page: ChromiumNativePage
        let host: BrowserExtensionSidePanelHost

        /// Whether the tab already shows this extension's panel.
        private var isShowing: Bool {
            host.panel(on: page.pageID)?.id == extensionID
        }

        // MARK: - Actions - Requests

        func open() {
            guard !isShowing else { return }
            present()
        }

        func close() {
            if isShowing { host.close(on: page.pageID) }
        }

        func toggle() {
            if isShowing { host.close(on: page.pageID) } else { present() }
        }

        private func present() {
            let action = ChromiumComposition.extensions.actions(for: page).first { $0.id == extensionID }
            BrowserExtensionSidePanelHost.present(
                extensionID, title: action?.displayName ?? extensionID,
                icon: action?.icon, page: page, host: host)
        }
    }
#endif
