import SwiftUI

struct BrowserTabIconActions: View {
    let tab: TabStateModel
    let favicons: FaviconAssets
    let isLoaded: Bool
    let pullNewIcon: (() -> Void)?
    let performIfCurrent: (() -> Void) -> Void
    let clearIcon: () -> Void
    let changeIcon: () -> Void

    var body: some View {
        if tab.nativeContent == nil {
            Button("Pull New Icon", systemImage: "arrow.clockwise.circle") {
                performIfCurrent { pullNewIcon?() }
            }
            .disabled(!isLoaded || pullNewIcon == nil)

        }

        Button("Clear Icon", systemImage: "xmark.circle") {
            performIfCurrent(clearIcon)
        }
        .disabled(tab.iconMode.followsPage && favicons.icon(of: tab.id) == nil)

        Button("Change Icon…", systemImage: "face.smiling") {
            performIfCurrent(changeIcon)
        }
    }
}
