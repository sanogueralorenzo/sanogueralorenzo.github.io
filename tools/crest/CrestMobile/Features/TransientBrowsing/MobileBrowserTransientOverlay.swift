import SwiftUI

struct MobileBrowserTransientOverlay: View {
    let presentationPhase: BrowserPeekPresentationPhase
    let spaceAccess: BrowserSpaceAccessController
    @State private var model: MobileBrowserTransientOverlayModel

    init(
        request: any MobileBrowserTransientRequest,
        presentationPhase: BrowserPeekPresentationPhase,
        browser: BrowserStore,
        pages: MobileBrowserPageStore,
        coordinator: BrowserTransientBrowsingCoordinator,
        spaceAccess: BrowserSpaceAccessController = BrowserSpaceAccessController(),
        preferences: BrowserTransientBrowsingPreferences? = nil,
        didPromote: @escaping () -> Void = {}
    ) {
        self.presentationPhase = presentationPhase
        self.spaceAccess = spaceAccess
        _model = State(
            initialValue: MobileBrowserTransientOverlayModel(
                request: request,
                browser: browser,
                pages: pages,
                coordinator: coordinator,
                spaceAccess: spaceAccess,
                preferences: preferences ?? .production(core: browser.core),
                didPromote: didPromote
            )
        )
    }

    init(
        model: MobileBrowserTransientOverlayModel,
        presentationPhase: BrowserPeekPresentationPhase,
        spaceAccess: BrowserSpaceAccessController
    ) {
        self.presentationPhase = presentationPhase
        self.spaceAccess = spaceAccess
        _model = State(initialValue: model)
    }

    var body: some View {
        MobileBrowserTransientOverlaySurface(
            model: model,
            presentationPhase: presentationPhase,
            spaceAccess: spaceAccess
        )
    }
}
