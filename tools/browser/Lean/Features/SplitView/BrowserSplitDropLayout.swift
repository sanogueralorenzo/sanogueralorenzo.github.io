import Foundation

/// Crest's content-slot rule and proportional insertion, shared by the native
/// placeholder and the committed split. Lifted cards retain their identities.
struct BrowserSplitDropLayout: Equatable {
    let ids: [UUID]
    let incoming: [UUID]
    let fractions: [Double]
    let insertionIndex: Int

    var orderedIDs: [UUID] {
        var seen = Set<UUID>()
        let carried = incoming.filter { seen.insert($0).inserted }
        var result = ids.filter { !seen.contains($0) }
        result.insert(contentsOf: carried, at: min(max(0, insertionIndex), result.count))
        return result
    }

    var projectedFractions: [Double] {
        let final = orderedIDs
        guard !final.isEmpty else { return [] }
        let source = fractions.count == ids.count ? fractions : ids.map { _ in 1 / Double(max(1, ids.count)) }
        let weights = Dictionary(uniqueKeysWithValues: zip(ids, source))
        let existingShare = Double(ids.count) / Double(final.count)
        return final.map { weights[$0].map { $0 * existingShare } ?? 1 / Double(final.count) }
    }

    static func insertionIndex(at point: CGPoint, frames: [CGRect], vertical: Bool) -> Int {
        let ordered = frames.filter { !$0.isEmpty }.sorted { vertical ? $0.minY < $1.minY : $0.minX < $1.minX }
        return ordered.prefix { vertical ? point.y > $0.midY : point.x > $0.midX }.count
    }

    static func frames(fractions: [Double], in bounds: CGRect, vertical: Bool, divider: CGFloat) -> [CGRect] {
        let available = max(
            0, (vertical ? bounds.height : bounds.width) - divider * CGFloat(max(0, fractions.count - 1)))
        var origin = vertical ? bounds.minY : bounds.minX
        return fractions.map { fraction in
            let size = available * fraction
            defer { origin += size + divider }
            return vertical
                ? CGRect(x: bounds.minX, y: origin, width: bounds.width, height: size)
                : CGRect(x: origin, y: bounds.minY, width: size, height: bounds.height)
        }
    }
}
