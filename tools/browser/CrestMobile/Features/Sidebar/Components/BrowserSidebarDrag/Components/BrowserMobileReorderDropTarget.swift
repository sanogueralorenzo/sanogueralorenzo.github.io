import SwiftUI
import UIKit

/// Native touch dragging feeds the shared reorder model. A committed drop
/// reveals its real row immediately, independently of UIKit preview cleanup.
struct BrowserMobileReorderDropTarget: UIViewRepresentable {
    let reorder: BrowserSidebarReorderContext
    let origin: CGPoint

    func makeUIView(context: Context) -> BrowserMobileReorderDropView {
        let view = BrowserMobileReorderDropView()
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: BrowserMobileReorderDropView, context: Context) {
        view.state = reorder.state
        view.commit = reorder.commit
        view.globalOrigin = origin
    }
}

final class BrowserMobileReorderDropView: UIView, UIDropInteractionDelegate {
    var state: BrowserSidebarReorderState?
    var commit: ((BrowserSidebarReorderDrop) -> Void)?
    var globalOrigin = CGPoint.zero
    init() {
        super.init(frame: .zero)
        addInteraction(UIDropInteraction(delegate: self))
    }

    required init?(coder: NSCoder) { nil }

    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: any UIDropSession) -> Bool {
        return state?.hasLiftInFlight == true && session.items.count == 1
            && session.localDragSession.flatMap { BrowserMobileDragRouter.activeSession(for: $0) } != nil
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: any UIDropSession) {
        track(session)
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: any UIDropSession)
        -> UIDropProposal
    {
        track(session)
        return UIDropProposal(operation: state?.resolvedTarget == nil ? .forbidden : .move)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: any UIDropSession) {
        track(session)
        guard let state, let local = session.localDragSession,
            let active = BrowserMobileDragRouter.activeSession(for: local)
        else { return }
        active.isDropping = true
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            // UIKit has already cancelled the source button's touch. Only the
            // simultaneous pointer gesture needs a post-release click guard.
            guard let drop = state.end(suppressReleaseActivation: false) else { return }
            commit?(drop)
        }
        window?.layoutIfNeeded()
    }

    func dropInteraction(
        _ interaction: UIDropInteraction, previewForDropping item: UIDragItem,
        withDefault defaultPreview: UITargetedDragPreview
    ) -> UITargetedDragPreview? {
        // Fade the held preview in place instead of waiting for a native flight
        // and a second handoff. The committed row is already visible and usable.
        nil
    }

    private func track(_ session: any UIDropSession) {
        let point = session.location(in: self)
        state?.update(pointer: CGPoint(x: globalOrigin.x + point.x, y: globalOrigin.y + point.y))
    }
}
