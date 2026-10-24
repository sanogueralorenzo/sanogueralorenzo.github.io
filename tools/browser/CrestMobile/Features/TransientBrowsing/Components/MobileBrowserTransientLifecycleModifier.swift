import SwiftUI

struct MobileBrowserTransientLifecycleModifier: ViewModifier {
    let model: MobileBrowserTransientOverlayModel
    let spaceAccess: BrowserSpaceAccessController

    func body(content: Content) -> some View {
        content
            .onChange(of: sourceIsLocked, initial: true) { _, isLocked in
                model.setSourceLocked(isLocked)
            }
            .onChange(of: sourceIsAvailable, initial: true) { _, isAvailable in
                model.setSourceAvailable(isAvailable)
            }
            .onDisappear(perform: model.handleDisappearance)
    }

    private var sourceIsLocked: Bool {
        guard let space = model.spaceModel else { return false }
        return spaceAccess.isLocked(space)
    }

    private var sourceIsAvailable: Bool {
        model.hasSource
    }
}
