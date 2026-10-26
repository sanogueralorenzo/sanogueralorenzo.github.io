import SwiftUI

struct BrowserRootBackdrop: View {
    let space: SpaceModel?
    let spaces: [SpaceModel]

    var body: some View {
        // Preserve coverage while colors change. Replacing this whole layer for
        // a Space ID briefly exposes the window background during a fade.
        SpaceBackdropBlend(spaces: spaces, selectedSpace: space) {
            BrowserWindowAtmosphere(space: $0)
        }
        // The window's background, wherever no page or control covers it, is
        // chrome: the title bar strip above a page and the gaps around it.
        .overlay { BrowserWindowTitleBarSurface() }
        .ignoresSafeArea()
    }
}
