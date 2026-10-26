import SwiftUI

struct BrowserGettingStartedTabAdapter: View {
    let runtime: BrowserNativeTabRuntime
    let bottomChromeHeight: CGFloat
    let openURL: (URL) -> Void

    var body: some View {
        BrowserMobileGettingStartedView(
            showsCompactNavigation: bottomChromeHeight > 0,
            state: runtime.model(BrowserGettingStartedState.self) { BrowserGettingStartedState() }
        )
    }
}
