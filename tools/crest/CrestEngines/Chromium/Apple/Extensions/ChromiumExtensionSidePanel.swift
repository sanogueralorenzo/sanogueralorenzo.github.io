#if CREST_CHROMIUM_HOST
    import AppKit
    import SwiftUI

    extension BrowserExtensionSidePanelHost {
        // MARK: - Static Variables

        /// How long to keep asking while the extension finishes enabling its panel.
        private static let enablementRetryDelays: [Duration] = [
            .milliseconds(100), .milliseconds(250), .milliseconds(600),
        ]

        // MARK: - Actions - Requests

        /// The action the extension action's context menu should offer, or `nil`
        /// when this extension has no side panel entry for `page`'s own tab.
        ///
        /// The panel document belongs to the engine and the card to `host`, so the
        /// engine's own dismissal only drops the card and a dismissal from the card
        /// only releases the document.
        static func opener(
            _ action: BrowserExtensionActionPresentation,
            page: ChromiumNativePage,
            host: BrowserExtensionSidePanelHost?
        ) -> (@MainActor () -> Void)? {
            guard let host, page.sidePanelScope(action.id) != .unavailable else { return nil }
            return { [weak host, weak page] in
                guard let host, let page, host.panel(on: page.pageID)?.id != action.id else { return }
                present(action.id, title: action.displayName, icon: action.icon, page: page, host: host)
            }
        }

        /// Applies a request the engine made for `page`'s own tab.
        static func route(
            _ request: SidePanelRequest,
            extensionID: String,
            page: ChromiumNativePage,
            host: BrowserExtensionSidePanelHost
        ) {
            request.take(through: ChromiumSidePanelRoute(extensionID: extensionID, page: page, host: host))
        }

        static func present(
            _ extensionID: String,
            title: String,
            icon: NSImage?,
            page: ChromiumNativePage,
            host: BrowserExtensionSidePanelHost,
            attempt: Int = 0
        ) {
            let pageID = page.pageID
            let view = page.openSidePanel(extensionID) { [weak host] in
                MainActor.assumeIsolated { host?.dismiss(extensionID, from: pageID) }
            }
            guard let view else {
                // An extension may enable its panel for the tab in the same turn it
                // asks to open it, and the engine can receive the open first.
                if attempt < enablementRetryDelays.count {
                    let delay = enablementRetryDelays[attempt]
                    Task { @MainActor [weak page, weak host] in
                        try? await Task.sleep(for: delay)
                        guard let page, let host, host.panel(on: pageID)?.id != extensionID else { return }
                        present(extensionID, title: title, icon: icon, page: page, host: host, attempt: attempt + 1)
                    }
                    return
                }
                ChromiumComposition.showNativeNotice(
                    "This extension's side panel is unavailable on this page.",
                    icon: "sidebar.right")
                return
            }
            // The engine has replaced any panel the tab had, whichever window
            // last showed it.
            BrowserExtensionSidePanelHosts.release(pageID)
            host.present(
                BrowserExtensionSidePanelHost.Panel(
                    id: extensionID, pageID: pageID, title: title, icon: icon, view: view,
                    close: { [weak page] in page?.closeSidePanel() },
                    follows: { [weak page] other in page?.sharesSidePanel(extensionID, with: other) ?? false }))
        }
    }
#endif
