import SwiftUI

struct BrowserRootPeekLayer: View {
    let model: BrowserRootModel
    let transientBrowsing: BrowserTransientBrowsingCoordinator
    let space: SpaceModel

    @Environment(\.layoutDirection) private var layoutDirection

    @ViewBuilder
    var body: some View {
        ForEach(
            transientBrowsing.peekRequests.filter {
                $0.assignment == BrowserSpaceRuntimeAssignment(space: space)
                    && $0.sourceTabID == model.browser.selectedTabID(in: space.id)
            }
        ) { request in
            BrowserPeekOverlay(
                request: request,
                browser: model.browser,
                pages: model.pages,
                coordinator: transientBrowsing,
                reservedLeadingWidth: 0,
                layoutDirection: layoutDirection,
                spaceAccess: model.spaceAccess
            )
            .environment(
                \.browserWebFocusRestorationGate,
                BrowserWebFocusRestorationGate(
                    browserChromeOwnsFocus: !request.isSelected(in: model.browser)
                        || !model.isWindowFocused || model.isAddressEditing || model.chrome.isCommandPalettePresented,
                    pageChromeOwnsFocus: false)
            )
            .zIndex(BrowserRootMetrics.peekZIndex)
        }
    }
}
