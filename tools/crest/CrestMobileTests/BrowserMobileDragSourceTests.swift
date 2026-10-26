import UIKit
import XCTest

@testable import CrestMobile

@MainActor
final class BrowserMobileDragSourceTests: XCTestCase, UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? { nil }

    func testCancelledLiftReleasesReorderLockWithoutEndingANewerDrag() throws {
        let window = try makeWindow()
        window.isHidden = false
        defer { window.isHidden = true }
        let host = UIView(frame: window.bounds)
        host.addInteraction(UIContextMenuInteraction(delegate: self))
        window.addSubview(host)
        let state = BrowserSidebarReorderState()
        let anchor = BrowserMobileDragAnchor()
        anchor.frame = CGRect(x: 10, y: 20, width: 280, height: 44)
        anchor.begin = {
            state.stage(
                item: .tab(.init(tabID: UUID(), spaceID: UUID(), profileID: UUID())),
                section: .tabs(placement: .current, folderID: nil))
            let token = state.sessionToken!
            return BrowserMobileDragSession(provider: NSItemProvider()) { state.cancel(session: token) }
        }
        host.addSubview(anchor)
        defer { anchor.removeFromSuperview() }
        let router = BrowserMobileDragRouter.forView(host)
        let interaction = UIDragInteraction(delegate: router)
        let first = NativeDragSession(point: CGPoint(x: 30, y: 40))
        let cancelledLift = NativeDragAnimator()
        _ = router.dragInteraction(interaction, itemsForBeginning: first)
        (router as any UIDragInteractionDelegate).dragInteraction?(
            interaction, willAnimateLiftWith: cancelledLift, session: first)
        XCTAssertTrue(state.hasLiftInFlight)

        // A context menu can cancel the lift before a drag session begins.
        // There need not be a didEndWith callback to release the pager lock.
        cancelledLift.complete(at: .start)
        XCTAssertFalse(state.hasLiftInFlight)
        XCTAssertNil(BrowserMobileDragRouter.activeSession(for: first))

        let second = NativeDragSession(point: CGPoint(x: 30, y: 40))
        let completedLift = NativeDragAnimator()
        _ = router.dragInteraction(interaction, itemsForBeginning: second)
        let active = try XCTUnwrap(BrowserMobileDragRouter.activeSession(for: second))
        (router as any UIDragInteractionDelegate).dragInteraction?(
            interaction, willAnimateLiftWith: completedLift, session: second)
        completedLift.complete(at: .end)
        XCTAssertTrue(state.hasLiftInFlight, "A successful lift must keep paging locked during the drag.")
        cancelledLift.complete(at: .start)
        router.dragInteraction(interaction, session: first, didEndWith: .cancel)
        XCTAssertTrue(state.hasLiftInFlight, "Late callbacks belong to the old drag.")
        XCTAssertTrue(BrowserMobileDragRouter.activeSession(for: second) === active)
        router.dragInteraction(interaction, session: second, didEndWith: .cancel)
        XCTAssertFalse(state.hasLiftInFlight)
    }

    private func makeWindow() throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        return window
    }

    private func source(name: String, frame: CGRect, began: @escaping (String) -> Void) -> BrowserMobileDragAnchor {
        let source = BrowserMobileDragAnchor()
        source.frame = frame
        source.begin = {
            began(name)
            return BrowserMobileDragSession(provider: NSItemProvider(), completion: {})
        }
        return source
    }

    private final class NativeDragAnimator: NSObject, UIDragAnimating {
        private var completions: [(UIViewAnimatingPosition) -> Void] = []

        func addAnimations(_ animations: @escaping () -> Void) {}
        func addCompletion(_ completion: @escaping (UIViewAnimatingPosition) -> Void) {
            completions.append(completion)
        }
        func complete(at position: UIViewAnimatingPosition) {
            for completion in completions { completion(position) }
        }
    }

    private final class NativeDragSession: NSObject, UIDragSession {
        let point: CGPoint
        var localContext: Any?
        var items: [UIDragItem] = []
        let allowsMoveOperation = true
        let isRestrictedToDraggingApplication = false

        init(point: CGPoint) { self.point = point }
        func location(in view: UIView) -> CGPoint { point }
        func hasItemsConforming(toTypeIdentifiers typeIdentifiers: [String]) -> Bool { true }
        func canLoadObjects(ofClass aClass: any NSItemProviderReading.Type) -> Bool { false }
    }
}
