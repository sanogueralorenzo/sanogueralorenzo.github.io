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

    /// A Space whose lock turns on re-renders locked at once, on the page the
    /// pager shows and on a neighbour a gesture revealed, and the lock ends that
    /// gesture.
    func testALockedSpaceRerendersLockedOnTheShownAndRevealedPages() throws {
        let store = nativeStore()
        var spaces: [SpaceModel] { store.spaceModels }
        var renderedRoots: [UUID: (isSelected: Bool, accessPolicy: SpaceAccessPolicy)] = [:]
        let (window, viewport) = makeNativeViewport()
        let presentation = SpacePagerPresentation()
        defer {
            viewport.teardown()
            window.contentView = nil
            window.close()
        }
        func update(selected: UUID) {
            viewport.update(
                spaces: spaces, selectedSpaceID: selected, isInteractionLocked: false,
                reduceMotion: false, layoutDirection: .leftToRight,
                presentation: presentation,
                selectSpace: { $0 },
                makeRoot: { space, isSelected in
                    renderedRoots[space.id] = (isSelected, space.settings.accessPolicy)
                    return self.nativeRoot(space, isSelected)
                })
        }
        update(selected: spaces[0].id)
        viewport.layoutSubtreeIfNeeded()

        store.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: spaces[0].id)
        update(selected: spaces[0].id)
        XCTAssertNil(viewport.motion)
        XCTAssertEqual(renderedRoots[spaces[0].id]?.accessPolicy, .deviceOwnerAuthentication)
        XCTAssertEqual(renderedRoots[spaces[0].id]?.isSelected, true)
        let revealing = try XCTUnwrap(viewport.beginInteractiveMotion())
        XCTAssertTrue(track(viewport, deltaX: -32, token: revealing))
        store.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: spaces[1].id)
        update(selected: spaces[0].id)
        XCTAssertNil(viewport.motion)
        XCTAssertEqual(renderedRoots[spaces[1].id]?.accessPolicy, .deviceOwnerAuthentication)
        XCTAssertFalse(viewport.endInteractiveMotion(velocity: -500, cancelled: false, token: revealing))
    }

    // Geometry/lifecycle cases deliver enough display frames for the given
    // drag to arrive. The burst case separately tests coalescing and speed.
    private func track(_ viewport: SpacePagerViewport<Text>, deltaX: CGFloat, token: UInt) -> Bool {
        guard viewport.updateInteractiveMotion(deltaX: deltaX, token: token) else { return false }
        for _ in 0..<60 { viewport.advanceFrame(interval: 1.0 / 60) }
        return true
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
