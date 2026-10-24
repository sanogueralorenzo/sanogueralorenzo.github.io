import UIKit
import XCTest

@testable import CrestMobile

@MainActor
final class BrowserMobileDragSourceTests: XCTestCase, UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? { nil }

    func testNativeCompletionBelongsToItsSessionAndPreservesSwiftUIDropMetadata() throws {
        let window = try makeWindow()
        window.isHidden = false
        defer { window.isHidden = true }
        let host = UIView(frame: window.bounds)
        host.addInteraction(UIContextMenuInteraction(delegate: self))
        window.addSubview(host)
        let source = BrowserMobileDragAnchor()
        source.frame = CGRect(x: 10, y: 20, width: 280, height: 44)
        var begins = 0
        var completions: [Int] = []
        source.begin = {
            begins += 1
            let generation = begins
            return BrowserMobileDragSession(provider: NSItemProvider()) { completions.append(generation) }
        }
        host.addSubview(source)
        let router = BrowserMobileDragRouter.forView(host)
        let interaction = UIDragInteraction(delegate: router)
        let first = NativeDragSession(point: CGPoint(x: 30, y: 40))
        let second = NativeDragSession(point: CGPoint(x: 40, y: 40))

        let item = try XCTUnwrap(router.dragInteraction(interaction, itemsForBeginning: first).first)
        XCTAssertNil(item.localObject)
        XCTAssertNil(first.localContext)
        _ = router.dragInteraction(interaction, itemsForBeginning: first)
        XCTAssertEqual(begins, 1, "UIKit asking again must not restage the same drag.")
        _ = router.dragInteraction(interaction, itemsForBeginning: second)
        router.dragInteraction(interaction, session: first, didEndWith: .cancel)
        router.dragInteraction(interaction, session: first, didEndWith: .cancel)
        XCTAssertEqual(completions, [1], "An old or duplicate completion cannot finish the newer drag.")
        router.dragInteraction(interaction, session: second, didEndWith: .move)
        XCTAssertEqual(completions, [1, 2])
        source.removeFromSuperview()
        XCTAssertFalse(host.interactions.contains { $0 is UIDragInteraction })
    }

    func testAbandonedNativeProviderQueryReleasesResourcesWhenSourceLeaves() throws {
        let window = try makeWindow()
        window.isHidden = false
        defer { window.isHidden = true }
        let host = UIView(frame: window.bounds)
        host.addInteraction(UIContextMenuInteraction(delegate: self))
        window.addSubview(host)
        let anchor = BrowserMobileDragAnchor()
        anchor.frame = CGRect(x: 10, y: 20, width: 280, height: 44)
        weak var retained: BrowserMobileDragSession?
        anchor.begin = {
            let record = BrowserMobileDragSession(provider: NSItemProvider(), completion: {})
            retained = record
            return record
        }
        host.addSubview(anchor)
        let router = BrowserMobileDragRouter.forView(host)
        let interaction = UIDragInteraction(delegate: router)
        autoreleasepool {
            let native = NativeDragSession(point: CGPoint(x: 30, y: 40))
            _ = router.dragInteraction(interaction, itemsForBeginning: native)
            XCTAssertNotNil(retained)
        }
        anchor.removeFromSuperview()
        XCTAssertNil(retained, "A provider query that never becomes a drag cannot retain a departed source's browser.")
        XCTAssertFalse(host.interactions.contains { $0 is UIDragInteraction })
    }

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

    func testHeldPreviewChangesShapeWithoutRestagingOrRenderingEveryMovement() throws {
        let window = try makeWindow()
        window.isHidden = false
        defer { window.isHidden = true }
        let host = UIView(frame: window.bounds)
        host.addInteraction(UIContextMenuInteraction(delegate: self))
        window.addSubview(host)
        let anchor = BrowserMobileDragAnchor()
        anchor.frame = CGRect(x: 10, y: 20, width: 280, height: 44)
        anchor.previewShape = .row
        anchor.begin = { BrowserMobileDragSession(provider: NSItemProvider(), completion: {}) }
        var widths: [CGFloat] = []
        anchor.makePreview = { width, _ in
            widths.append(width)
            let size =
                anchor.previewShape == .pinnedTile
                ? CGSize(width: 64, height: 52) : CGSize(width: width, height: 44)
            return UIView(frame: CGRect(origin: .zero, size: size))
        }
        defer { anchor.makePreview = nil }
        host.addSubview(anchor)
        let router = BrowserMobileDragRouter.forView(host)
        let interaction = UIDragInteraction(delegate: router)
        let session = NativeDragSession(point: CGPoint(x: 30, y: 40))
        let item = try XCTUnwrap(router.dragInteraction(interaction, itemsForBeginning: session).first)
        XCTAssertTrue(router.dragInteraction(interaction, itemsForBeginning: session).first === item)
        anchor.refreshPreview()
        XCTAssertEqual(widths, [280])

        // Displacing the source must not change the captured row width.
        anchor.frame.size.width = 0
        anchor.previewShape = .pinnedTile
        anchor.refreshPreview()
        let tile = try XCTUnwrap(item.previewProvider?())
        XCTAssertEqual(tile.view.bounds.size, CGSize(width: 64, height: 52))
        anchor.refreshPreview()
        XCTAssertEqual(widths, [280, 280])
        anchor.previewShape = .row
        anchor.refreshPreview()
        XCTAssertEqual(item.previewProvider?()?.view.bounds.size, CGSize(width: 280, height: 44))
        XCTAssertEqual(widths, [280, 280, 280])

        router.dragInteraction(interaction, session: session, didEndWith: .cancel)
        anchor.previewShape = .pinnedTile
        anchor.refreshPreview()
        XCTAssertEqual(widths.count, 3, "A completed native session must stop observing its source.")
        anchor.removeFromSuperview()
    }

    func testSourceSelectionRespectsNestedRowsClippingAndHiddenAncestors() throws {
        let window = try makeWindow()
        window.isHidden = false
        defer { window.isHidden = true }
        let host = UIView(frame: window.bounds)
        host.addInteraction(UIContextMenuInteraction(delegate: self))
        window.addSubview(host)
        let clipping = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        clipping.clipsToBounds = true
        host.addSubview(clipping)
        var chosen: [String] = []
        let group = source(name: "group", frame: CGRect(x: 10, y: 20, width: 280, height: 160)) { chosen.append($0) }
        let tab = source(name: "tab", frame: CGRect(x: 30, y: 60, width: 250, height: 44)) { chosen.append($0) }
        clipping.addSubview(group)
        clipping.addSubview(tab)
        let router = BrowserMobileDragRouter.forView(host)
        let interaction = UIDragInteraction(delegate: router)
        let session = NativeDragSession(point: CGPoint(x: 50, y: 80))
        XCTAssertEqual(router.dragInteraction(interaction, itemsForBeginning: session).count, 1)
        XCTAssertEqual(chosen, ["tab"])
        router.dragInteraction(interaction, session: session, didEndWith: .cancel)

        clipping.isHidden = true
        XCTAssertTrue(
            router.dragInteraction(interaction, itemsForBeginning: NativeDragSession(point: session.point)).isEmpty)
        clipping.isHidden = false
        clipping.frame.size.height = 50
        XCTAssertTrue(
            router.dragInteraction(interaction, itemsForBeginning: NativeDragSession(point: session.point)).isEmpty)
        tab.removeFromSuperview()
        group.removeFromSuperview()
    }

    func testMobileDropImmediatelyRevealsAndEnablesTheDroppedTab() throws {
        let state = BrowserSidebarReorderState()
        let space = BrowserSpaceRuntimeAssignment(spaceID: UUID(), profileID: UUID())
        let section = BrowserSidebarReorderSection.tabs(placement: .current, folderID: nil)
        let item = BrowserSidebarReorderItem.tab(
            .init(tabID: UUID(), spaceID: space.spaceID, profileID: space.profileID))
        let frame = CGRect(x: 10, y: 100, width: 280, height: 44)
        state.register(row: .init(id: item.id, space: space, section: section, frame: frame), owner: UUID())
        state.register(zone: .init(target: .section(section), frame: frame), for: UUID())
        state.begin(item: item, section: section, at: CGPoint(x: 100, y: 120))
        let token = try XCTUnwrap(state.sessionToken)
        state.update(pointer: CGPoint(x: 100, y: 140))
        XCTAssertNotNil(state.end(suppressReleaseActivation: false))
        XCTAssertFalse(state.hasLiftInFlight, "The native destination must stop intercepting taps after commit.")
        XCTAssertFalse(state.suppressesActivation, "The dropped tab must activate without waiting for preview cleanup.")
        XCTAssertFalse(state.hidesSource(item.id))
        XCTAssertNil(state.landingPreview)
        state.cancel(session: token)
        XCTAssertFalse(state.suppressesActivation, "Native source completion must not reintroduce a click guard.")
    }

    func testDropUsesOriginatingSessionWhenUIKitCopiesTheDragItem() throws {
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
            return BrowserMobileDragSession(provider: NSItemProvider(), completion: {})
        }
        host.addSubview(anchor)
        let router = BrowserMobileDragRouter.forView(host)
        let interaction = UIDragInteraction(delegate: router)
        let native = NativeDragSession(point: CGPoint(x: 30, y: 40))
        let original = try XCTUnwrap(router.dragInteraction(interaction, itemsForBeginning: native).first)
        let copy = UIDragItem(itemProvider: original.itemProvider)
        let incoming = NativeDropSession(items: [copy], localDragSession: native)
        let view = BrowserMobileReorderDropView()
        view.state = state
        let drop = UIDropInteraction(delegate: view)
        XCTAssertTrue(view.dropInteraction(drop, canHandle: incoming))
        incoming.localDragSession = nil
        XCTAssertFalse(view.dropInteraction(drop, canHandle: incoming), "Foreign JSON cannot commit a local lift.")
        router.dragInteraction(interaction, session: native, didEndWith: .cancel)
        anchor.removeFromSuperview()
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

    private final class NativeDropSession: NSObject, UIDropSession {
        let items: [UIDragItem]
        var localDragSession: (any UIDragSession)?
        let allowsMoveOperation = true
        let isRestrictedToDraggingApplication = false
        let progress = Progress(totalUnitCount: 1)
        var progressIndicatorStyle = UIDropSessionProgressIndicatorStyle.none

        init(items: [UIDragItem], localDragSession: any UIDragSession) {
            self.items = items
            self.localDragSession = localDragSession
        }

        func location(in view: UIView) -> CGPoint { .zero }
        func hasItemsConforming(toTypeIdentifiers typeIdentifiers: [String]) -> Bool { true }
        func canLoadObjects(ofClass aClass: any NSItemProviderReading.Type) -> Bool { false }
        func loadObjects(
            ofClass aClass: any NSItemProviderReading.Type,
            completion: @escaping ([any NSItemProviderReading]) -> Void
        ) -> Progress { progress }
    }
}
