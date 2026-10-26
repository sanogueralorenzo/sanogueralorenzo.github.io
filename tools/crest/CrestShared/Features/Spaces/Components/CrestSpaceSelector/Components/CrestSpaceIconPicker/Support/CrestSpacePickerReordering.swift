import SwiftUI

/// A temporary horizontal layout, committed only when the pointer is released.
/// This keeps the lifted button alive while its neighbors move into the gap.
struct CrestSpacePickerReordering {
    private(set) var sourceID: UUID?
    private(set) var targetID: UUID?
    private(set) var translation = CGSize.zero
    private(set) var pointer = CGPoint.zero
    private var startLocation = CGPoint.zero
    private var scrollTranslation: CGFloat = 0
    private var viewport = CGRect.zero
    private var canDrop = false

    mutating func update(
        source: UUID, ids: [UUID], frames: [UUID: CGRect],
        start: CGPoint, pointer: CGPoint, viewport: CGRect = .zero
    ) {
        guard sourceID == nil || sourceID == source,
            ids.contains(source), let sourceFrame = frames[source]
        else { return }
        sourceID = source
        self.pointer = pointer
        startLocation = start
        self.viewport = viewport
        // Keep the lifted crest visible even when the pointer enters the
        // flanking arrows. Scrolling brings each new destination beneath it.
        let visibleX =
            viewport.isEmpty
            ? pointer.x
            : min(
                max(pointer.x, viewport.minX + sourceFrame.width / 2),
                viewport.maxX - sourceFrame.width / 2)
        translation = CGSize(width: visibleX - start.x - scrollTranslation, height: pointer.y - start.y)
        canDrop = pointer.y >= sourceFrame.minY - 24 && pointer.y <= sourceFrame.maxY + 24
        targetID =
            canDrop
            ? ids.min {
                abs((frames[$0]?.midX ?? .infinity) - visibleX) < abs((frames[$1]?.midX ?? .infinity) - visibleX)
            }
            : source
    }

    /// Frames have already been translated by the scroll view's actual bounds
    /// movement. Compensate the lifted icon and re-evaluate the stationary pointer.
    mutating func contentMoved(by offset: CGFloat, ids: [UUID], frames: [UUID: CGRect]) {
        guard let sourceID else { return }
        scrollTranslation += offset
        update(source: sourceID, ids: ids, frames: frames, start: startLocation, pointer: pointer, viewport: viewport)
    }

    static func autoscrollStep(at pointer: CGPoint, in viewport: CGRect) -> CGFloat {
        guard !viewport.isEmpty,
            viewport.insetBy(dx: -48, dy: -24).contains(pointer)
        else { return 0 }
        let edge = min(24, viewport.width / 3)
        if pointer.x < viewport.minX + edge {
            return -6 * min(1, (viewport.minX + edge - pointer.x) / edge)
        }
        if pointer.x > viewport.maxX - edge {
            return 6 * min(1, (pointer.x - viewport.maxX + edge) / edge)
        }
        return 0
    }

    func offset(for id: UUID, ids: [UUID], frames: [UUID: CGRect]) -> CGSize {
        guard let sourceID, let targetID,
            let source = ids.firstIndex(of: sourceID), let target = ids.firstIndex(of: targetID),
            let index = ids.firstIndex(of: id)
        else { return .zero }
        if id == sourceID { return translation }
        let displacedIndex: Int
        if source < target, index > source, index <= target {
            displacedIndex = index - 1
        } else if source > target, index >= target, index < source {
            displacedIndex = index + 1
        } else {
            return .zero
        }
        guard let frame = frames[id], let destination = frames[ids[displacedIndex]] else { return .zero }
        return CGSize(width: destination.minX - frame.minX, height: 0)
    }

    mutating func end() -> (source: UUID, target: UUID)? {
        defer { self = Self() }
        guard canDrop, let sourceID, let targetID, sourceID != targetID else { return nil }
        return (sourceID, targetID)
    }
}
