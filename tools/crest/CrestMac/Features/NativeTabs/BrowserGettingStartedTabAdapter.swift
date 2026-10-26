import SwiftUI

struct BrowserGettingStartedTabAdapter: View {
    let runtime: BrowserNativeTabRuntime
    let bottomChromeHeight: CGFloat
    let openURL: (URL) -> Void

    var body: some View {
        BrowserGettingStartedView(
            state: runtime.model(BrowserGettingStartedState.self) { BrowserGettingStartedState() },
            openURL: openURL
        )
    }
}
