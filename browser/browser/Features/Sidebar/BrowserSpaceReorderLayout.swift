import Foundation

/// Crest's Space-picker displacement: the session order stays unchanged until
/// release, while the buttons between source and destination step aside.
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
        let x = min(max(pointer.x, viewport.minX + source.width / 2), viewport.maxX - source.width / 2)
        targetID = ids.filter { frames[$0] != nil }.min {
            abs(frames[$0]!.midX - x) < abs(frames[$1]!.midX - x)
        }
    }

    var destination: (id: UUID, after: Bool)? {
        guard let targetID, sourceID != targetID,
            let source = ids.firstIndex(of: sourceID), let target = ids.firstIndex(of: targetID)
        else { return nil }
        return (targetID, source < target)
    }

    func offset(for id: UUID) -> CGFloat {
        guard id != sourceID, let targetID,
            let source = ids.firstIndex(of: sourceID), let target = ids.firstIndex(of: targetID),
            let index = ids.firstIndex(of: id), let frame = frames[id]
        else { return 0 }
        let displaced: Int
        if source < target, index > source, index <= target {
            displaced = index - 1
        } else if source > target, index >= target, index < source {
            displaced = index + 1
        } else {
            return 0
        }
        return (frames[ids[displaced]]?.minX ?? frame.minX) - frame.minX
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
