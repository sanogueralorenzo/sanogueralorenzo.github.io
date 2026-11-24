import Foundation

/// Space-picker displacement adapted from Crest. Commit the order only on release.
struct BrowserSpaceReorderLayout: Equatable {
    let sourceID: UUID
    let ids: [UUID]
    var frames: [UUID: CGRect]
    private(set) var pointer = CGPoint.zero
    private(set) var targetID: UUID?

    mutating func update(at pointer: CGPoint, viewport: CGRect) {
        self.pointer = pointer
        guard let source = frames[sourceID], !viewport.isEmpty,
            pointer.y >= source.minY - 24, pointer.y <= source.maxY + 24,
            pointer.x >= viewport.minX - 48, pointer.x <= viewport.maxX + 48
        else {
            targetID = nil
            return
        }
        let x = min(max(pointer.x, viewport.minX), viewport.maxX)
        targetID = ids.compactMap { id -> (id: UUID, frame: CGRect)? in
            guard let frame = frames[id]?.intersection(viewport), !frame.isEmpty else { return nil }
            return (id, frame)
        }.min { abs($0.frame.midX - x) < abs($1.frame.midX - x) }?.id
    }

    var destination: (id: UUID, after: Bool)? {
        guard let targetID, sourceID != targetID,
            let source = ids.firstIndex(of: sourceID), let target = ids.firstIndex(of: targetID)
        else { return nil }
        return (targetID, source < target)
    }

    var landingFrame: CGRect? {
        guard let destination, let target = frames[destination.id], var source = frames[sourceID] else { return nil }
        source.origin.x = target.midX > source.midX ? target.maxX - source.width : target.minX
        return source
    }

    func offset(for id: UUID) -> CGFloat {
        guard id != sourceID, let targetID,
            let source = ids.firstIndex(of: sourceID), let target = ids.firstIndex(of: targetID),
            let index = ids.firstIndex(of: id), let frame = frames[sourceID]
        else { return 0 }
        let neighborIndex: Int
        if source < target, index > source, index <= target {
            neighborIndex = source + 1
        } else if source > target, index >= target, index < source {
            neighborIndex = source - 1
        } else {
            return 0
        }
        guard let neighbor = frames[ids[neighborIndex]] else { return 0 }
        return neighbor.midX > frame.midX ? frame.minX - neighbor.minX : frame.maxX - neighbor.maxX
    }

    mutating func contentMoved(by delta: CGFloat, viewport: CGRect) {
        frames = frames.mapValues { $0.offsetBy(dx: delta, dy: 0) }
        update(at: pointer, viewport: viewport)
    }

    static func autoscrollStep(at pointer: CGPoint, in viewport: CGRect) -> CGFloat {
        guard !viewport.isEmpty, viewport.insetBy(dx: -48, dy: -24).contains(pointer) else { return 0 }
        let edge = min(24, viewport.width / 3)
        if pointer.x < viewport.minX + edge {
            return -6 * min(1, (viewport.minX + edge - pointer.x) / edge)
        }
        if pointer.x > viewport.maxX - edge {
            return 6 * min(1, (pointer.x - viewport.maxX + edge) / edge)
        }
        return 0
    }
}
