import CoreGraphics

/// The same fractional Space coordinate drives every presentation leaf. A
/// step from the last Space to the first carries it up to one Space past the
/// last, and a step back from the first up to one before it, where the two
/// ends meet.
struct SpacePagerInterpolation {
    let lower: Int
    let upper: Int
    let fraction: CGFloat

    init?(position: CGFloat, count: Int) {
        guard count > 0, position.isFinite else { return nil }
        if count > 2, position > CGFloat(count - 1), position <= CGFloat(count) {
            (lower, upper, fraction) = (count - 1, 0, position - CGFloat(count - 1))
            return
        }
        if count > 2, position < 0, position >= -1 {
            (lower, upper, fraction) = (count - 1, 0, position + 1)
            return
        }
        let position = min(CGFloat(count - 1), max(0, position))
        lower = Int(position.rounded(.down))
        upper = min(count - 1, lower + 1)
        fraction = position - CGFloat(lower)
    }

    /// Where the strip places the page at `index` around `position`: its own
    /// index, or one strip length away where a step joins the two ends. Two
    /// Spaces are already neighbours both ways, so they never wrap.
    static func index(_ index: Int, near position: CGFloat, count: Int) -> Int {
        guard count > 2, position.isFinite else { return index }
        return index + count * Int(((position - CGFloat(index)) / CGFloat(count)).rounded())
    }

    func frame(from start: CGRect, to end: CGRect) -> CGRect {
        CGRect(
            x: start.minX + (end.minX - start.minX) * fraction,
            y: start.minY + (end.minY - start.minY) * fraction,
            width: start.width + (end.width - start.width) * fraction,
            height: start.height + (end.height - start.height) * fraction)
    }

    static func backdropOpacity(at position: CGFloat, index: Int) -> Float {
        Float(min(1, max(0, position - CGFloat(index) + 1)))
    }
}
