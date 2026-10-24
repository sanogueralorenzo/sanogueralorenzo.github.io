import SwiftUI

struct BrowserQuickWindowPageContent: View {
    let model: BrowserQuickWindowModel

    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    var body: some View {
        Group {
            if let page = model.page, let pages = model.pages {
                BrowserWebContentView(
                    page: page,
                    browser: model.browser,
                    pages: pages,
                    isQuickWindowPage: true
                )
            } else if model.pageLease?.wasReleasedForMemoryPressure == true {
                BrowserQuickWindowReleasedPageView(
                    reduceTransparency: reduceTransparency,
                    restore: model.restorePage
                )
            } else {
                BrowserQuickWindowLookupStartView(space: model.spaceModel?.identity)
            }
        }
    }
}
