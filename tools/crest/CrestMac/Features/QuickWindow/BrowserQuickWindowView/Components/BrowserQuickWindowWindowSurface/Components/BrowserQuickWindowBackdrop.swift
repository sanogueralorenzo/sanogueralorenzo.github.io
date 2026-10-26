import SwiftUI

struct BrowserQuickWindowBackdrop: View {
    let space: SpaceModel?

    var body: some View {
        BrowserWindowAtmosphere(space: space)
            // The window's background, wherever no page or control covers it, is
            // chrome, the toolbar strip under the title bar included.
            .overlay { BrowserWindowTitleBarSurface() }
            .ignoresSafeArea()
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserQuickWindowBackdrop(space: BrowserCommandPalettePreviewFixture.space)
            .frame(width: 540, height: 360)
    }
#endif
