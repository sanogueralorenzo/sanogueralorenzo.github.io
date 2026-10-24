import SwiftUI

struct BrowserQuickWindowActivityLifecycleModifier: ViewModifier {
    let model: BrowserQuickWindowModel
    let spaceAccess: BrowserSpaceAccessController
    let dismiss: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task(id: model.selectedAssignment) {
                model.preparePage(isActive: scenePhase == .active)
            }
            .onChange(of: model.wasClosedByPage) { _, closed in
                if closed { dismiss() }
            }
            .task(id: model.archiveTimer) {
                guard await model.waitUntilArchiveIsDue() else { return }
                model.archivePageIfNeeded()
                dismiss()
            }
            .onChange(of: scenePhase) { _, phase in
                model.setActive(phase == .active)
                guard phase != .active else { return }
                if phase == .inactive {
                    spaceAccess.lockAllForInactiveScene()
                } else {
                    spaceAccess.lockAll()
                }
            }
    }
}
