import SwiftUI

/// Native scrolling is the clock on touch devices. This non-observable adapter
/// publishes geometry to presentation leaves without invalidating sidebar rows.
@MainActor
final class TouchSpacePagerProgress {
    // MARK: - Variables

    private var phase: SpacePagerPresentation.Phase = .idle
    private var generation: UInt = 0
    private var position: CGFloat?
    private var destinationIndex: Int?
    /// Whether a person drives the scroll under way, or drove the last one to
    /// come to rest. Keyboard focus scrolls the pager too, to show an item it
    /// moved to on another Space's page, and that must never choose the Space.
    private(set) var isPersonDriven = true

    // MARK: - Actions - Scrolling

    func update(position: CGFloat, ids: [UUID], presentation: SpacePagerPresentation?) {
        guard position.isFinite, !ids.isEmpty else { return }
        if let previous = self.position, abs(position - previous) > 0.000_001 {
            destinationIndex = Int(position.rounded(position > previous ? .up : .down))
        }
        self.position = min(CGFloat(ids.count - 1), max(0, position))
        publish(ids: ids, presentation: presentation)
    }

    func update(phase: ScrollPhase, ids: [UUID], presentation: SpacePagerPresentation?) {
        let next: SpacePagerPresentation.Phase =
            switch phase {
            case .idle: .idle
            case .tracking, .interacting: .tracking
            case .decelerating, .animating: .settling
            @unknown default: .idle
            }
        if next == .tracking && self.phase != .tracking { generation &+= 1 }
        if next == .tracking {
            isPersonDriven = true
        } else if self.phase == .idle && next == .settling {
            isPersonDriven = false
        }
        self.phase = next
        publish(ids: ids, presentation: presentation)
    }

    // MARK: - Actions - Presentation

    private func publish(ids: [UUID], presentation: SpacePagerPresentation?) {
        guard let position, !ids.isEmpty else { return }
        let nearest = min(
            ids.count - 1,
            max(0, phase == .idle ? Int(position.rounded()) : destinationIndex ?? Int(position.rounded())))
        presentation?.publish(
            .init(
                generation: generation, spaceIDs: ids,
                position: position, phase: phase, destinationID: ids[nearest]))
    }
}
