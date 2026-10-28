import AppKit
import Observation
import SwiftUI

/// One internal drag shared by every window of the browser session.
@MainActor @Observable
final class BrowserSidebarDragSession {
    private(set) var payload: BrowserDragPayload?
    private(set) var lift: BrowserSidebarReorderState.Lift?
    private(set) var committed = false
    private(set) var landingIDs: Set<UUID> = []
    @ObservationIgnored private(set) var source: BrowserSidebarDragSourceView?
    @ObservationIgnored private var landingToken: UUID?
    @ObservationIgnored private var landingPreview: BrowserSidebarDragPreview?
    @ObservationIgnored private var suppressedUntil = Date.distantPast

    var suppressesActivation: Bool { payload != nil || Date() < suppressedUntil }

    @discardableResult
    func begin(_ payload: BrowserDragPayload, from source: BrowserSidebarDragSourceView, in store: BrowserStore) -> Bool
    {
        guard self.payload == nil else { return false }
        landingPreview?.cancel()
        clearLanding()
        self.payload = payload
        self.source = source
        committed = false
        if payload.kind == .space {
            for context in store.owner.contexts.values where !context.isClosed {
                context.sidebarReorder.beginSpace(payload.spaceID, in: context)
            }
        }
        if let space = store.session.spaces.first(where: { $0.id == payload.spaceID }) {
            lift = store.sidebarReorder.makeLift(payload, in: space)
            if let lift {
                for context in store.owner.contexts.values where !context.isClosed {
                    context.sidebarReorder.begin(lift, in: context)
                }
            }
        }
        return true
    }

    func commit(_ action: () -> Bool) -> Bool {
        guard payload != nil, !committed else { return false }
        let accepted = action()
        if accepted { committed = true }
        return accepted
    }

    func finish(accepted: Bool, preview: BrowserSidebarDragPreview?, in owner: BrowserSessionOwner) {
        guard payload != nil else { return }
        // AppKit can deliver the source button's release after the drop.
        suppressedUntil = Date().addingTimeInterval(0.25)
        let token = UUID()
        landingToken = token
        if let lift {
            landingIDs = lift.rootIDs.union(payload?.ids ?? [])
        } else if let payload, payload.kind == .space {
            landingIDs = [payload.spaceID]
        }
        let landing = owner.contexts.values.compactMap { $0.sidebarReorder.landingFrame(in: $0) }.first
        payload = nil
        source = nil
        lift = nil
        withAnimation(
            LeanMotion.dragSource.unlessReducingMotion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        ) {
            for context in owner.contexts.values {
                context.isDragging = false
                context.sidebarReorder.finish()
            }
        }
        landingPreview = preview
        if let preview {
            preview.finish(accepted: accepted, landing: landing) { [weak self] in
                guard let self, self.landingToken == token else { return }
                self.clearLanding()
            }
        } else {
            clearLanding()
        }
    }

    private func clearLanding() {
        landingToken = nil
        landingIDs = []
        landingPreview = nil
    }
}
