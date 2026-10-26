import SwiftUI

/// Where a link that arrives from outside a page ends up.
struct BrowserLinkSettingsPane: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    var body: some View {
        BrowserSettingsPane(.links) {
            BrowserLinkSettingsContent(browser: browser, spaceAccess: spaceAccess, links: browser.linkPreferences)
        }
    }
}
