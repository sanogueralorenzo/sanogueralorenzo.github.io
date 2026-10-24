import AppKit
import SwiftUI
import XCTest

@testable import Crest

@MainActor
final class SpaceScrollGestureTests: XCTestCase {
    func testOneHorizontalIntentPerGesturePreservesVerticalAndOutsideScrolling() {
        struct Event {
            let input: SpaceScrollGestureRecognizer.Input
            var isInside = true
        }
        struct Scenario {
            let name: String
            let events: [Event]
            let decisions: [SpaceScrollGestureRecognizer.Decision]
        }

        let scenarios: [Scenario] = [
            Scenario(
                name: "Long phased gesture and momentum never repeat, then a fresh gesture can step",
                events: [
                    Event(input: input(-100, at: 0, phase: .began)),
                    Event(input: input(-100, at: 1, phase: .changed)),
                    Event(input: input(100, at: 2, phase: .changed)),
                    Event(input: input(0, at: 2.1, phase: .ended), isInside: false),
                    Event(input: input(-100, at: 2.2, momentum: true), isInside: false),
                    Event(input: input(-100, at: 3, momentum: true), isInside: false),
                    Event(input: input(100, at: 3.1, phase: .began)),
                ],
                decisions: [.step(.next), .consumed, .consumed, .consumed, .consumed, .consumed, .step(.previous)]
            ),
            Scenario(
                name: "Vertical axis stays native even when later deltas lean horizontally",
                events: [
                    Event(input: input(1, y: 100, at: 0, phase: .began)),
                    Event(input: input(-150, y: 1, at: 0.1, phase: .changed)),
                    Event(input: input(0, at: 0.2, phase: .ended)),
                    Event(input: input(-100, at: 0.3, momentum: true)),
                    Event(input: input(-100, at: 0.4, phase: .began)),
                ],
                decisions: [.passThrough, .passThrough, .passThrough, .passThrough, .step(.next)]
            ),
            Scenario(
                name: "Phase-less continuous burst rearms only after an idle gap",
                events: [
                    Event(input: input(-100, at: 0)),
                    Event(input: input(-100, at: 0.2)),
                    Event(input: input(-100, at: 0.4)),
                    Event(input: input(100, at: 0.6)),
                    Event(input: input(100, at: 0.8)),
                    Event(input: input(100, at: 2)),
                ],
                decisions: [.step(.next), .consumed, .consumed, .consumed, .consumed, .step(.previous)]
            ),
            Scenario(
                name: "Wheel notches use their own units and one step per burst",
                events: [
                    Event(input: input(-1, at: 0, precise: false)),
                    Event(input: input(-10, at: 0.05, precise: false)),
                    Event(input: input(1, at: 0.1, precise: false)),
                    Event(input: input(1, at: 1, precise: false)),
                ],
                decisions: [.step(.next), .consumed, .consumed, .step(.previous)]
            ),
            Scenario(
                name: "Returning across the origin before acceptance cancels without a compensating step",
                events: [
                    Event(input: input(-20, at: 0, phase: .began)),
                    Event(input: input(40, at: 0.1, phase: .changed)),
                    Event(input: input(-200, at: 0.2, phase: .changed)),
                    Event(input: input(0, at: 0.3, phase: .cancelled)),
                    Event(input: input(-100, at: 0.4, phase: .began)),
                ],
                decisions: [.consumed, .consumed, .consumed, .consumed, .step(.next)]
            ),
            Scenario(
                name: "A gesture starting outside stays untouched, and a later inside gesture works",
                events: [
                    Event(input: input(-100, at: 0, phase: .began), isInside: false),
                    Event(input: input(-100, at: 0.1, phase: .changed)),
                    Event(input: input(0, at: 0.2, phase: .ended)),
                    Event(input: input(-100, at: 0.3, phase: .began)),
                    Event(input: input(0, at: 0.4, phase: .ended)),
                    Event(input: input(100, at: 0.5, phase: .began), isInside: false),
                ],
                decisions: [.passThrough, .passThrough, .passThrough, .step(.next), .consumed, .passThrough]
            ),
            Scenario(
                name: "Momentum without a recognized horizontal gesture passes through",
                events: [
                    Event(input: input(-100, at: 0, momentum: true)),
                    Event(input: input(-100, at: 0.1, momentum: true)),
                    Event(input: input(-100, at: 0.2, phase: .began)),
                ],
                decisions: [.passThrough, .passThrough, .step(.next)]
            ),
        ]

        for scenario in scenarios {
            XCTContext.runActivity(named: scenario.name) { _ in
                var recognizer = SpaceScrollGestureRecognizer()
                let actual = scenario.events.map { recognizer.consume($0.input, isInside: $0.isInside) }
                XCTAssertEqual(actual, scenario.decisions)
            }
        }
    }

    func testNativePagingTracksPointsAndSettlesBeforeCommitting() async throws {
        var spaces = nativeSpaces()
        var selections: [UUID] = []
        var actualSelection = spaces[0].id
        var acceptsSelection = true
        let (window, viewport) = makeNativeViewport()
        let presentation = SpacePagerPresentation()
        let iconObserver = NSObject()
        let backdropObserver = NSObject()
        var iconSnapshot: SpacePagerPresentation.Snapshot?
        var backdropSnapshot: SpacePagerPresentation.Snapshot?
        presentation.observe(owner: iconObserver) { iconSnapshot = $0 }
        presentation.observe(owner: backdropObserver) { backdropSnapshot = $0 }
        let foreground = SpaceForegroundPresentation()
        foreground.connect(
            presentation,
            tones: spaces.enumerated().map { .init(id: $0.element.id, white: $0.offset == 0 ? 0 : 1) },
            selectedSpaceID: spaces[0].id)

        defer {
            viewport.teardown()
            window.contentView = nil
            window.close()
        }
        func update(selected: UUID) {
            actualSelection = selected
            viewport.update(
                spaces: spaces, selectedSpaceID: selected, isInteractionLocked: false,
                reduceMotion: false, layoutDirection: .leftToRight,
                presentation: presentation,
                selectSpace: {
                    selections.append($0)
                    if acceptsSelection { actualSelection = $0 }
                    return actualSelection
                },
                makeRoot: nativeRoot)
        }
        // Keep a previously visited distant page cached alongside the two
        // pages participating in this gesture.
        update(selected: spaces[2].id)
        update(selected: spaces[0].id)
        viewport.layoutSubtreeIfNeeded()
        assertPageFrames(viewport, spaces: spaces, selectedIndex: 0)
        let source = try XCTUnwrap(
            viewport.subviews.compactMap { $0 as? SpacePageHost<Text> }.first {
                $0.hostingView.rootView.assignment.spaceID == spaces[0].id
            })
        let distant = try XCTUnwrap(
            viewport.subviews.compactMap { $0 as? SpacePageHost<Text> }.first {
                $0.hostingView.rootView.assignment.spaceID == spaces[2].id
            })
        let distantFrame = distant.frame
        let token = try XCTUnwrap(viewport.beginInteractiveMotion())
        var distance: CGFloat = 0
        for delta in [CGFloat(-3), -17, -90, 12] {
            distance += delta
            XCTAssertTrue(track(viewport, deltaX: delta, token: token))
            XCTAssertEqual(source.frame.minX, distance, accuracy: 0.001)
            XCTAssertEqual(distant.frame, distantFrame, "Offscreen layouts must stay stationary during tracking")
            XCTAssertFalse(distant.isHidden, "Cached layouts must stay attached through focus and page handoffs")
            XCTAssertEqual(
                try XCTUnwrap(presentation.snapshot).position, -distance / viewport.bounds.width,
                accuracy: 0.000_001)
            XCTAssertEqual(presentation.snapshot?.phase, .tracking)
            XCTAssertEqual(iconSnapshot, presentation.snapshot)
            XCTAssertEqual(backdropSnapshot, presentation.snapshot)
            XCTAssertEqual(
                Double(try XCTUnwrap(foreground.position)), Double(-distance / viewport.bounds.width),
                accuracy: 0.000_001)

        }
        XCTAssertEqual(viewport.selectedSpaceID, spaces[0].id)
        XCTAssertTrue(selections.isEmpty)

        // A short, fast flick can finish a page without first dragging halfway.
        XCTAssertTrue(viewport.endInteractiveMotion(velocity: -1200, cancelled: false, token: token))
        XCTAssertEqual(distant.frame, distantFrame, "Settling must not animate an offscreen layout")
        XCTAssertFalse(distant.isHidden, "Settling must not discard a retained layout")
        XCTAssertTrue(distant.layer?.animationKeys()?.isEmpty ?? true)
        XCTAssertTrue(selections.isEmpty, "Finger release must not interrupt the settling frames")
        XCTAssertEqual(presentation.snapshot?.phase, .settling)
        XCTAssertEqual(
            try XCTUnwrap(presentation.snapshot).position, -distance / viewport.bounds.width,
            accuracy: 0.000_001)
        try await awaitSettlement(viewport)
        XCTAssertEqual(selections, [spaces[1].id])
        XCTAssertEqual(presentation.snapshot?.phase, .idle)
        XCTAssertEqual(presentation.snapshot?.position, 1)
        XCTAssertEqual(foreground.position, 1)
        XCTAssertEqual(iconSnapshot, presentation.snapshot)
        XCTAssertEqual(backdropSnapshot, presentation.snapshot)
        presentation.removeObserver(owner: backdropObserver)
        let lastBackdropSnapshot = backdropSnapshot
        XCTAssertEqual(viewport.presentationSpaceID, spaces[1].id)
        XCTAssertFalse(viewport.endInteractiveMotion(velocity: -1200, cancelled: false, token: token))
        XCTAssertEqual(selections, [spaces[1].id])

        // The native selection receipt can precede SwiftUI reconciliation.
        // Returning immediately must still undo the accepted B selection.
        let returning = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(track(viewport, deltaX: 224, token: returning))
        XCTAssertEqual(iconSnapshot, presentation.snapshot)
        XCTAssertEqual(backdropSnapshot, lastBackdropSnapshot, "Removing a background must leave the icon connected")
        XCTAssertTrue(viewport.endInteractiveMotion(velocity: 500, cancelled: false, token: returning))
        try await awaitSettlement(viewport)
        XCTAssertEqual(selections, [spaces[1].id, spaces[0].id])
        XCTAssertEqual(actualSelection, spaces[0].id)
        XCTAssertEqual(foreground.position, 0)
        foreground.disconnect()
        update(selected: spaces[0].id)
        viewport.step(.next)
        try await awaitSettlement(viewport)
        update(selected: spaces[1].id)
        XCTAssertEqual(selections, [spaces[1].id, spaces[0].id, spaces[1].id])

        update(selected: spaces[1].id)
        window.setContentSize(NSSize(width: 321, height: 501))
        viewport.layoutSubtreeIfNeeded()
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(20))
        assertPageFrames(viewport, spaces: spaces, selectedIndex: 1)
        window.setContentSize(NSSize(width: 320, height: 500))
        viewport.layoutSubtreeIfNeeded()

        let cancelled = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(track(viewport, deltaX: 64, token: cancelled))
        XCTAssertTrue(viewport.endInteractiveMotion(velocity: 1000, cancelled: true, token: cancelled))
        XCTAssertNotNil(viewport.motion, "Cancellation must settle back instead of snapping at finger release")
        try await awaitSettlement(viewport)
        XCTAssertEqual(
            selections, [spaces[1].id, spaces[0].id, spaces[1].id],
            "Cancellation must not select a different Space")

        acceptsSelection = false
        let refused = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(track(viewport, deltaX: -240, token: refused))
        XCTAssertTrue(viewport.endInteractiveMotion(velocity: 0, cancelled: false, token: refused))
        try await awaitSettlement(viewport)
        XCTAssertEqual(selections, [spaces[1].id, spaces[0].id, spaces[1].id, spaces[2].id])
        XCTAssertEqual(viewport.selectedSpaceID, spaces[1].id)
        XCTAssertEqual(viewport.presentationSpaceID, spaces[1].id)
        XCTAssertNotNil(viewport.beginInteractiveMotion(), "A refused selection must not leave the viewport locked")

        // Consecutive commands may admit a new neighbor before SwiftUI delivers
        // the first selection receipt. It must enter from beside the live page.
        spaces = nativeSpaces()
        acceptsSelection = true
        update(selected: spaces[0].id)
        viewport.step(.next)
        try await awaitSettlement(viewport)
        viewport.step(.next)
        let incoming = try XCTUnwrap(
            viewport.subviews.compactMap { $0 as? SpacePageHost<Text> }.first {
                $0.hostingView.rootView.assignment.spaceID == spaces[2].id
            })
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertGreaterThan(
            try XCTUnwrap(incoming.layer?.presentation()).frame.minX, viewport.bounds.width / 2,
            "A newly admitted page must animate in from its adjacent position")
        try await awaitSettlement(viewport)
        XCTAssertEqual(Array(selections.suffix(2)), [spaces[1].id, spaces[2].id])
    }

    func testNativePagingPreservesInterruptedPositionAndRejectsInvalidatedGestures() async throws {
        let store = nativeStore()
        var spaces: [SpaceModel] { store.spaceModels }
        var selections: [UUID] = []
        var renderedRoots: [UUID: (isSelected: Bool, name: String, accessPolicy: SpaceAccessPolicy)] = [:]
        let (window, viewport) = makeNativeViewport()
        let presentation = SpacePagerPresentation()
        defer {
            viewport.teardown()
            window.contentView = nil
            window.close()
        }
        func update(selected: UUID, locked: Bool = false) {
            viewport.update(
                spaces: spaces, selectedSpaceID: selected, isInteractionLocked: locked,
                reduceMotion: false, layoutDirection: .leftToRight,
                presentation: presentation,
                selectSpace: {
                    selections.append($0)
                    return $0
                },
                makeRoot: { space, isSelected in
                    renderedRoots[space.id] = (isSelected, space.settings.name, space.settings.accessPolicy)
                    return self.nativeRoot(space, isSelected)
                })
        }
        update(selected: spaces[0].id)
        viewport.layoutSubtreeIfNeeded()
        let source = try XCTUnwrap(
            viewport.subviews.compactMap { $0 as? SpacePageHost<Text> }.first {
                $0.hostingView.rootView.assignment.spaceID == spaces[0].id
            })
        let first = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(track(viewport, deltaX: -224, token: first))
        XCTAssertTrue(viewport.endInteractiveMotion(velocity: -500, cancelled: false, token: first))
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(20))
        let sourceLayer = try XCTUnwrap(source.layer)
        let before = (sourceLayer.presentation() ?? sourceLayer).frame.minX
        let second = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertEqual(source.frame.minX, before, accuracy: 0.5)
        XCTAssertEqual(viewport.presentationSpaceID, spaces[1].id)
        XCTAssertEqual(viewport.selectedSpaceID, spaces[0].id)
        XCTAssertTrue(selections.isEmpty)
        XCTAssertFalse(viewport.endInteractiveMotion(velocity: -500, cancelled: false, token: first))

        // A new leftward gesture starts from the inherited rightward offset of
        // the incoming page. Its first point must not clamp that offset to zero.
        let inherited = source.frame.minX
        XCTAssertTrue(track(viewport, deltaX: -1, token: second))
        XCTAssertEqual(source.frame.minX, inherited - 1, accuracy: 0.001)
        viewport.layoutSubtreeIfNeeded()
        CATransaction.flush()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(
            (sourceLayer.presentation() ?? sourceLayer).frame.minX, inherited - 1, accuracy: 0.5,
            "An interrupted animation must stay stopped after AppKit layout and the next frame")
        XCTAssertTrue(track(viewport, deltaX: -255, token: second))
        XCTAssertTrue(viewport.endInteractiveMotion(velocity: -900, cancelled: false, token: second))
        XCTAssertTrue(selections.isEmpty)
        try await awaitSettlement(viewport)
        XCTAssertEqual(selections, [spaces[2].id])
        update(selected: spaces[2].id)

        let superseded = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(track(viewport, deltaX: 128, token: superseded))
        update(selected: spaces[0].id)
        XCTAssertEqual(viewport.selectedSpaceID, spaces[0].id)
        XCTAssertNil(viewport.motion, "A distant direct selection must not leave a compressed strip to interrupt")
        XCTAssertFalse(viewport.endInteractiveMotion(velocity: 1000, cancelled: false, token: superseded))
        update(selected: spaces[0].id, locked: true)
        XCTAssertNil(viewport.beginInteractiveMotion())
        XCTAssertEqual(viewport.presentationSpaceID, spaces[0].id)
        XCTAssertEqual(selections, [spaces[2].id])

        update(selected: spaces[0].id)
        let edge = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(track(viewport, deltaX: 39, token: edge))
        XCTAssertEqual(source.frame.minX, 0, "The first Space must not expose empty space beyond its edge")
        XCTAssertTrue(track(viewport, deltaX: 1, token: edge))
        XCTAssertEqual(source.frame.minX, 0)
        XCTAssertTrue(viewport.endInteractiveMotion(velocity: 1000, cancelled: false, token: edge))
        XCTAssertNil(viewport.motion, "An unmoved page has no return animation")
        let edgeRestart = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(track(viewport, deltaX: 100, token: edgeRestart))
        XCTAssertEqual(source.frame.minX, 0)
        XCTAssertTrue(viewport.endInteractiveMotion(velocity: 0, cancelled: true, token: edgeRestart))
        XCTAssertNil(viewport.motion)
        XCTAssertEqual(selections, [spaces[2].id])

        viewport.step(.next)
        try await awaitSettlement(viewport)
        XCTAssertEqual(selections, [spaces[2].id, spaces[1].id])
        // An external selection supersedes the pending B receipt, even when
        // SwiftUI never delivered that intermediate selection to the viewport.
        update(selected: spaces[2].id)
        try await awaitSettlement(viewport)
        let activeHost = try XCTUnwrap(
            viewport.subviews.compactMap { $0 as? SpacePageHost<Text> }.first {
                $0.hostingView.rootView.assignment.spaceID == spaces[2].id
            })
        XCTAssertFalse(activeHost.isAccessibilityHidden())

        // Command slides reuse ready roots; completion receives the latest
        // content and role even if another update arrives during the animation.
        update(selected: spaces[0].id)
        update(selected: spaces[1].id)
        XCTAssertNotNil(viewport.motion)
        XCTAssertEqual(renderedRoots[spaces[1].id]?.isSelected, false)
        store.updateSpaceIdentity(spaces[1].id, name: "Changed while settling", symbol: "globe", accent: .indigo)
        update(selected: spaces[1].id)
        try await awaitSettlement(viewport)
        XCTAssertEqual(renderedRoots[spaces[1].id]?.isSelected, true)
        XCTAssertEqual(renderedRoots[spaces[1].id]?.name, spaces[1].settings.name)

        // Resize and detachment can bypass the animation's completion. They
        // must still refresh the authoritative page before returning input.
        update(selected: spaces[2].id)
        XCTAssertNotNil(viewport.motion)
        store.updateSpaceIdentity(spaces[2].id, name: "Changed before resize", symbol: "globe", accent: .indigo)
        update(selected: spaces[2].id)
        window.setContentSize(NSSize(width: 321, height: 501))
        viewport.layoutSubtreeIfNeeded()
        XCTAssertNil(viewport.motion)
        XCTAssertEqual(renderedRoots[spaces[2].id]?.isSelected, true)
        XCTAssertEqual(renderedRoots[spaces[2].id]?.name, spaces[2].settings.name)
        update(selected: spaces[1].id)
        XCTAssertNotNil(viewport.motion)
        store.updateSpaceIdentity(spaces[1].id, name: "Changed before reattachment", symbol: "globe", accent: .indigo)
        update(selected: spaces[1].id)
        window.contentView = nil
        window.contentView = viewport
        XCTAssertNil(viewport.motion)
        XCTAssertEqual(renderedRoots[spaces[1].id]?.isSelected, true)
        XCTAssertEqual(renderedRoots[spaces[1].id]?.name, spaces[1].settings.name)

        // A privacy-policy change supersedes both a simultaneous command and
        // an existing physical gesture; an old open-policy root cannot linger.
        store.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: spaces[0].id)
        update(selected: spaces[0].id)
        XCTAssertNil(viewport.motion)
        XCTAssertEqual(renderedRoots[spaces[0].id]?.accessPolicy, .deviceOwnerAuthentication)
        XCTAssertEqual(renderedRoots[spaces[0].id]?.isSelected, true)
        let protected = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(track(viewport, deltaX: -32, token: protected))
        store.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: spaces[1].id)
        update(selected: spaces[0].id)
        XCTAssertNil(viewport.motion)
        XCTAssertEqual(renderedRoots[spaces[1].id]?.accessPolicy, .deviceOwnerAuthentication)
        XCTAssertFalse(viewport.endInteractiveMotion(velocity: -500, cancelled: false, token: protected))

        update(selected: spaces[2].id)
        let detached = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(track(viewport, deltaX: 64, token: detached))
        window.contentView = nil
        XCTAssertNil(viewport.motion)
        XCTAssertEqual(presentation.snapshot?.phase, .idle)
        XCTAssertEqual(presentation.snapshot?.position, 2)
        window.contentView = viewport
        let tornDown = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(track(viewport, deltaX: 64, token: tornDown))
        viewport.teardown()
        XCTAssertEqual(presentation.snapshot?.phase, .idle)
        XCTAssertEqual(presentation.snapshot?.position, 2)
        XCTAssertEqual(selections, [spaces[2].id, spaces[1].id])
    }

    // Geometry/lifecycle cases deliver enough display frames for the given
    // drag to arrive. The burst case separately tests coalescing and speed.
    private func track(_ viewport: SpacePagerViewport<Text>, deltaX: CGFloat, token: UInt) -> Bool {
        guard viewport.updateInteractiveMotion(deltaX: deltaX, token: token) else { return false }
        for _ in 0..<60 { viewport.advanceFrame(interval: 1.0 / 60) }
        return true
    }

    private func awaitSettlement(_ viewport: SpacePagerViewport<Text>) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while viewport.motion != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(viewport.motion, "The native animation must deliver its completion")
    }

    private func assertPageFrames(
        _ viewport: SpacePagerViewport<Text>, spaces: [SpaceModel], selectedIndex: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for host in viewport.subviews.compactMap({ $0 as? SpacePageHost<Text> }) {
            guard let index = spaces.firstIndex(where: { $0.id == host.hostingView.rootView.assignment.spaceID })
            else { continue }
            let expectedX = CGFloat(index - selectedIndex) * viewport.bounds.width
            XCTAssertEqual(host.frame.minX, expectedX, accuracy: 0.001, file: file, line: line)
            XCTAssertEqual(host.frame.size, viewport.bounds.size, file: file, line: line)
            XCTAssertEqual(host.layer?.affineTransform(), .identity, file: file, line: line)
            if let visible = host.layer?.presentation() {
                XCTAssertEqual(visible.frame.minX, expectedX, accuracy: 0.5, file: file, line: line)
            }
        }
    }

    private func makeNativeViewport() -> (NSWindow, SpacePagerViewport<Text>) {
        let window = NSWindow(
            contentRect: CGRect(x: -10000, y: -10000, width: 320, height: 500),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let viewport = SpacePagerViewport<Text>(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        window.contentView = viewport
        window.orderFront(nil)
        return (window, viewport)
    }

    /// A window over `count` Spaces, whose read model the pager draws.
    private func nativeStore(count: Int = 3) -> BrowserStore {
        BrowserStore(
            seed: SessionState.Seed(
                spaces: (0..<count).map { index in
                    SpaceState.Seed(
                        name: "Space \(index)",
                        symbol: "globe", accent: .indigo, folders: [], tabs: [])
                }))
    }

    private func nativeSpaces(count: Int = 3) -> [SpaceModel] {
        nativeStore(count: count).spaceModels
    }

    private func nativeRoot(_ space: SpaceModel, _ isSelected: Bool) -> SpacePageRoot<Text> {
        SpacePageRoot(
            content: Text(space.settings.name),
            assignment: BrowserSpaceRuntimeAssignment(space: space),
            objects: SpacePageObjects(
                sidebarInteraction: nil, extensionSidePanel: nil, downloadFeedback: nil, passkeyAccess: nil,
                softwareUpdates: nil, agentEndpoint: nil, core: nil))
    }

    private func input(
        _ x: CGFloat, y: CGFloat = 0, at timestamp: TimeInterval,
        phase: SpaceScrollGestureRecognizer.Phase = .none, precise: Bool = true, momentum: Bool = false
    ) -> SpaceScrollGestureRecognizer.Input {
        .init(deltaX: x, deltaY: y, timestamp: timestamp, isPrecise: precise, phase: phase, isMomentum: momentum)
    }
}
