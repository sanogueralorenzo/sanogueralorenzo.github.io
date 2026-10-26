import AppKit
import SwiftUI

/// The system sign-in page, with its current address visible throughout redirects.
struct BrowserAuthenticationWindowContent: View {
    let page: BrowserPage
    let browser: BrowserStore
    let pages: BrowserPagePool
    let chrome: BrowserChromeState
    let initialURL: URL
    weak var window: NSWindow?
    let dismiss: () -> Void

    var body: some View {
        BrowserWebContentView(page: page, browser: browser, pages: pages, isAuthenticationPage: true)
            .safeAreaInset(edge: .top) {
                Text(verbatim: page.live.displayURL?.absoluteString ?? initialURL.absoluteString)
                    .font(.callout)
                    .lineLimit(1)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity)
                    .padding(CrestSpacing.small)
                    .background(.bar)
            }
            .overlay { BrowserNoticeLayer(chrome: chrome) }
            .modifier(BrowserChromeAppearancePersistence())
            .onChange(of: page.live.title, initial: true) { _, title in
                window?.title = title.isEmpty ? String(localized: "Sign In") : title
            }
            .onChange(of: browser.core.state.pages[page.corePage.id]?.id) { _, pageID in
                if pageID == nil { dismiss() }
            }
    }
}
