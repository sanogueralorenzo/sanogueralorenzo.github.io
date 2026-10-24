import SwiftUI

struct MobileTransientBrowsingOverlay: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore?
    let coordinator: BrowserTransientBrowsingCoordinator
    let spaceAccess: BrowserSpaceAccessController
    let didPromote: () -> Void

    var showsPeeks = true

    var body: some View {
        ZStack {
            if showsPeeks {
                ForEach(coordinator.peekRequests.filter { $0.isSelected(in: browser) }) { request in
                    overlay(
                        MobileTransientBrowsingPresentation(
                            request: request, phase: coordinator.presentationPhase(for: request) ?? .committed)
                    )
                }
            }
            if let request = coordinator.quickWindowRequest {
                overlay(MobileTransientBrowsingPresentation(request: request, phase: .committed))
            }
        }
    }

    private func overlay(_ presentation: MobileTransientBrowsingPresentation) -> some View {
        MobileTransientBrowsingRequestOverlay(
            presentation: presentation,
            browser: browser,
            pages: pages,
            coordinator: coordinator,
            spaceAccess: spaceAccess,
            didPromote: didPromote
        )
    }
}
