import SwiftUI

struct BrowserQuickWindowPageSurface: View {
    @Environment(\.browserChromeAppearance) private var appearance
    @Environment(\.layoutDirection) private var layoutDirection
    let model: BrowserQuickWindowModel

    var body: some View {
        BrowserRootContentSurface(
            cornerRadius: appearance.pageCornerRadius,
            seamWidth: appearance.seamWidth,
            frameInsets: frameInsets,
            usesTransparentInnerSurface:
                model.page == nil
                && model.pageLease?.wasReleasedForMemoryPressure != true,
            showsBoundary: !appearance.borderless
        ) {
            BrowserQuickWindowPageContent(model: model)
        }
    }

    private var frameInsets: EdgeInsets {
        var insets = appearance.pageInsets(docked: false, direction: layoutDirection)
        insets.top = max(insets.top, BrowserQuickWindowLayout.toolbarTopPadding)
        return insets
    }
}
