import AppKit

@MainActor
struct BrowserMacWindowDropAction {
    let coordinator: BrowserMacWindowCoordinator
    let sourceWindowID: UUID
    let open: (BrowserMacWindowRequest) -> Void

    func perform(
        _ item: BrowserSidebarReorderItem, at point: CGPoint,
        grabFraction: CGPoint = CGPoint(x: 0.5, y: 0.5)
    ) -> Bool {
        guard !coordinator.isInsideWindow(sourceWindowID, screenPoint: point) else { return false }
        guard case .tab(let tab) = item else { return true }
        if let target = coordinator.windowID(at: point, excluding: sourceWindowID) {
            _ = coordinator.move(tab, from: sourceWindowID, to: target)
        } else if !coordinator.isInsideAnyWindow(screenPoint: point),
            let request = coordinator.prepareTearOff(tab, from: sourceWindowID, at: point, grabFraction: grabFraction)
        {
            open(request)
        }
        return true
    }
}
