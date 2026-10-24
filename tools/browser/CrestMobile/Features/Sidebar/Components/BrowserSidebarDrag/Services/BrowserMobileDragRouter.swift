import UIKit

/// One native source interaction per context-menu host. Row anchors supply geometry,
/// payload and preview; shared reorder state continues to own every drop rule.
@MainActor
final class BrowserMobileDragRouter: NSObject, UIDragInteractionDelegate {
    private static let routers = NSMapTable<UIView, BrowserMobileDragRouter>.weakToStrongObjects()
    private let anchors = NSHashTable<BrowserMobileDragAnchor>.weakObjects()
    private weak var host: UIView?
    private var window: UIWindow? { host?.window }
    private lazy var interaction = UIDragInteraction(delegate: self)
    private let sessions = NSMapTable<AnyObject, BrowserMobileDragSession>.weakToStrongObjects()

    static func forView(_ view: UIView) -> BrowserMobileDragRouter {
        if let router = routers.object(forKey: view) { return router }
        let router = BrowserMobileDragRouter()
        router.host = view
        routers.setObject(router, forKey: view)
        return router
    }

    static func activeSession(for session: any UIDragSession) -> BrowserMobileDragSession? {
        for router in routers.objectEnumerator()?.allObjects as? [BrowserMobileDragRouter] ?? [] {
            if let active = router.sessions.object(forKey: session) { return active }
        }
        return nil
    }

    func add(_ anchor: BrowserMobileDragAnchor) {
        anchors.add(anchor)
        if interaction.view == nil {
            interaction.isEnabled = true
            host?.addInteraction(interaction)
        }
    }

    func remove(_ anchor: BrowserMobileDragAnchor) {
        anchors.remove(anchor)
        detachIfUnused()
    }

    private func detachIfUnused() {
        if anchors.allObjects.isEmpty, sessions.keyEnumerator().allObjects.isEmpty {
            // Weak keys disappear before Foundation releases their values.
            // No live native session remains to issue a terminal callback.
            sessions.removeAllObjects()
            interaction.view?.removeInteraction(interaction)
            if let host, Self.routers.object(forKey: host) === self {
                Self.routers.removeObject(forKey: host)
            }
        }
    }

    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: any UIDragSession) -> [UIDragItem]
    {
        guard let window else { return [] }
        if let active = sessions.object(forKey: session) {
            return [active.item]
        }
        let point = session.location(in: window)
        // A tab inside an expanded folder or split group owns the narrower
        // source. The enclosing header remains the source for the whole block.
        let source = anchors.allObjects
            .filter { $0.visibleFrame(in: window).contains(point) }
            .min { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
        guard let source, let active = source.begin?() else { return [] }
        active.source = source
        active.previewShape = source.previewShape
        active.previewView = source.makePreview?(source.bounds.width, window.screen.scale)
        active.sourceFrame = source.convert(source.bounds, to: window)
        // Keep ownership here. Filling native localContext/localObject made
        // SwiftUI's destination reject otherwise valid JSON drops on iOS 26.
        sessions.setObject(active, forKey: session)
        return [active.item]
    }

    func refreshPreview(for source: BrowserMobileDragAnchor) {
        guard let window else { return }
        for active in sessions.objectEnumerator()?.allObjects as? [BrowserMobileDragSession] ?? [] {
            guard !active.isDropping, active.source === source, active.previewShape != source.previewShape,
                let view = source.makePreview?(active.sourceFrame.width, window.screen.scale)
            else { continue }
            active.previewShape = source.previewShape
            active.previewView = view
            // UIKit owns movement and the transition between these snapshots.
            // Only a changed destination shape requests a new image.
            active.item.previewProvider = {
                let parameters = UIDragPreviewParameters()
                parameters.backgroundColor = .clear
                return UIDragPreview(view: view, parameters: parameters)
            }
        }
    }

    func dragInteraction(
        _ interaction: UIDragInteraction, previewForLifting item: UIDragItem, session: any UIDragSession
    ) -> UITargetedDragPreview? {
        guard let window, let active = sessions.object(forKey: session), let view = active.previewView else {
            return nil
        }
        let frame = active.sourceFrame
        let size = view.bounds.size
        let parameters = UIDragPreviewParameters()
        parameters.backgroundColor = .clear
        return UITargetedDragPreview(
            view: view, parameters: parameters,
            target: UIDragPreviewTarget(
                container: window, center: CGPoint(x: frame.midX, y: frame.minY + size.height / 2)))
    }

    func dragInteraction(_ interaction: UIDragInteraction, sessionAllowsMoveOperation session: any UIDragSession)
        -> Bool
    {
        true
    }

    func dragInteraction(
        _ interaction: UIDragInteraction, willAnimateLiftWith animator: any UIDragAnimating,
        session: any UIDragSession
    ) {
        // A context menu can win during the lift, before a drag session starts.
        // That cancellation must release the staged reorder lock too.
        animator.addCompletion { [weak self] position in
            guard position == .start else { return }
            self?.finish(session)
        }
    }

    func dragInteraction(_ interaction: UIDragInteraction, prefersFullSizePreviewsFor session: any UIDragSession)
        -> Bool
    {
        true
    }

    func dragInteraction(
        _ interaction: UIDragInteraction, session: any UIDragSession, didEndWith operation: UIDropOperation
    ) {
        finish(session)
    }

    private func finish(_ session: any UIDragSession) {
        let active = sessions.object(forKey: session)
        sessions.removeObject(forKey: session)
        active?.finish()
        detachIfUnused()
    }
}
