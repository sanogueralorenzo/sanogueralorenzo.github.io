import SwiftUI

struct MobileBrowserTransientOverlaySurface: View {
    let model: MobileBrowserTransientOverlayModel
    let presentationPhase: BrowserPeekPresentationPhase
    let spaceAccess: BrowserSpaceAccessController

    var body: some View {
        BrowserTransientOverlayContent(
            requestID: model.request.id,
            space: model.spaceModel,
            spaces: model.availableSpaceModels,
            spaceAccess: spaceAccess,
            // The overlay is the whole screen here, so a Space disappearing
            // under it leaves nothing to explain the loss against.
            unavailableSpacePresentation: .immediateDismissal,
            selectSpace: model.selectLockedSpace,
            dismissUnavailable: model.dismissUnavailableRequest
        ) {
            MobileBrowserTransientUnlockedContent(
                model: model,
                presentationPhase: presentationPhase
            )
        }
        .modifier(
            MobileBrowserTransientLifecycleModifier(
                model: model,
                spaceAccess: spaceAccess
            )
        )
    }
}
