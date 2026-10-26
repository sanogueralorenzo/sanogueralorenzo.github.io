import SwiftUI

struct MobileTransientBrowsingRequestOverlay: View {
    /// Above the browser's own chrome, which a transient overlay always covers.
    private static let overlayLayer: Double = 20

    let presentation: MobileTransientBrowsingPresentation?
    let browser: BrowserStore
    let pages: MobileBrowserPageStore?
    let coordinator: BrowserTransientBrowsingCoordinator
    let spaceAccess: BrowserSpaceAccessController
    let didPromote: () -> Void

    @ViewBuilder
    var body: some View {
        if let presentation, let pages {
            MobileBrowserTransientOverlay(
                request: presentation.request,
                presentationPhase: presentation.phase,
                browser: browser,
                pages: pages,
                coordinator: coordinator,
                spaceAccess: spaceAccess,
                didPromote: didPromote
            )
            .id(presentation.request.renderIdentity)
            .zIndex(Self.overlayLayer)
        } else if let presentation {
            MobileTransientBrowsingPreviewSurface(
                request: presentation.request
            )
            .id(presentation.request.renderIdentity)
            .zIndex(Self.overlayLayer)
        }
    }
}
