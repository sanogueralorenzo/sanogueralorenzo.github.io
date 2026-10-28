import SwiftUI

/// The panel hosts the engine can reach, one per browser window.
///
/// `chrome.sidePanel.open()`, `chrome.sidePanel.close()` and an action click
/// that toggles a panel all arrive from the engine with a page identifier and
/// no view context, so the window whose row owns the card has to be found
/// rather than injected the way the extension controls receive it.
@MainActor
enum BrowserExtensionSidePanelHosts {
    /// Weak by construction: the window's own root model owns its panel host.
    private final class Reference { weak var host: BrowserExtensionSidePanelHost? }
    private static var hosts: [UUID: Reference] = [:]

    static func register(_ host: BrowserExtensionSidePanelHost, for window: UUID) {
        let reference = Reference()
        reference.host = host
        hosts[window] = reference
    }
    static func forget(_ window: UUID) { hosts[window] = nil }
    static func host(for window: UUID) -> BrowserExtensionSidePanelHost? {
        guard let host = hosts[window]?.host else {
            hosts[window] = nil
            return nil
        }
        return host
    }
    /// The page's panel document went away with the page, or gave way to
    /// another, in whichever window last showed it.
    static func release(_ pageID: UUID) {
        for reference in hosts.values { reference.host?.release(pageID) }
    }
}

/// Publishes a window's panel host for the engine's own side-panel requests,
/// and has it follow the tab the window focuses.
struct BrowserExtensionSidePanelRegistration: ViewModifier {
    let host: BrowserExtensionSidePanelHost
    /// The window's pages, whose focused card is the tab the panel follows.
    let pages: BrowserPagePool

    func body(content: Content) -> some View {
        content
            .onAppear { BrowserExtensionSidePanelHosts.register(host, for: pages.windowID) }
            .onDisappear { BrowserExtensionSidePanelHosts.forget(pages.windowID) }
            .onChange(of: pages.activePage?.corePage.id, initial: true) { _, pageID in
                host.focus(on: pageID)
            }
    }
}
