import SwiftUI

struct MobileBrowserSidebarLayout: View {
    let configuration: MobileBrowserSidebarContentConfiguration

    var body: some View {
        MobileBrowserSidebarBottomChromeLayout(configuration: configuration) {
            MobileBrowserSidebarPager(configuration: configuration)
        }
    }
}
