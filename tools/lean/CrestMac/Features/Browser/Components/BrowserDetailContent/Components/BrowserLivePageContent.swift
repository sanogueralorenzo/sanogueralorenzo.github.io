import SwiftUI

struct BrowserLivePageContent: View {
    let page: BrowserPage?
    let browser: BrowserStore
    let pages: BrowserPagePool

    var body: some View {
        if let page {
            BrowserWebContentView(
                page: page,
                browser: browser,
                pages: pages
            )
        } else {
            BrowserUnloadedPageSurface()
        }
    }
}
