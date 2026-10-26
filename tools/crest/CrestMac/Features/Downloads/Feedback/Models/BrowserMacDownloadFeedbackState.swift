import Foundation
import Observation

/// A window consumes each start once, including starts it cannot present.
/// Returning to a Space or revealing the sidebar never replays old feedback.
@Observable
@MainActor
final class BrowserMacDownloadFeedbackState {
    struct Flight: Identifiable {
        let id: UUID
        let path: BrowserMacDownloadFlightPath?
    }

    private(set) var flights: [Flight] = []
    @ObservationIgnored private var observedIDs: Set<UUID> = []
    @ObservationIgnored private var previousContext: BrowserMacDownloadFeedbackContext?

    @discardableResult
    func reconcile(
        events: [BrowserDownloadFeedbackEvent],
        context: BrowserMacDownloadFeedbackContext
    ) -> Bool {
        let currentIDs = Set(events.map(\.id))
        defer {
            observedIDs = currentIDs
            previousContext = context
        }
        guard previousContext != nil else { return false }
        if previousContext != context { cancel() }
        // The flights are worked out apart and stored only when they differ:
        // every tab switch changes the context, and a write announces the
        // flights to the window even when there are none.
        var next = flights.filter { currentIDs.contains($0.id) }
        defer { if next.map(\.id) != flights.map(\.id) { flights = next } }
        guard context.isVisible, let window = context.windowIdentifier else { return false }
        let newEvents = events.filter {
            !observedIDs.contains($0.id)
                && $0.source.windowIdentifier == window
                && $0.spaceID == context.spaceID
                && $0.profileID == context.profileID
        }
        for event in newEvents {
            next.append(Flight(id: event.id, path: path(for: event, context: context)))
        }
        next = Array(next.suffix(BrowserDownloadFeedbackEvent.maximumVisible))
        return !newEvents.isEmpty
    }

    func arrive(_ id: UUID) {
        flights.removeAll { $0.id == id }
    }

    func cancel() {
        if !flights.isEmpty { flights.removeAll() }
    }

    private func path(
        for event: BrowserDownloadFeedbackEvent,
        context: BrowserMacDownloadFeedbackContext
    ) -> BrowserMacDownloadFlightPath? {
        guard !context.reduceMotion,
            let destination = context.destination,
            !destination.isEmpty,
            context.bounds.contains(destination),
            context.bounds.contains(event.source.pointInGlobal)
        else { return nil }
        return BrowserMacDownloadFlightPath(
            source: event.source.pointInGlobal,
            destination: CGPoint(x: destination.midX, y: destination.midY),
            bounds: context.bounds
        )
    }
}
