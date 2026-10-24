import QuartzCore
import SwiftUI

/// One release timeline for the page, picker, background, and fixed chrome.
/// Tracking still follows the pager's displayed position directly.
struct SpacePagerSettlement: Equatable {
    let startPosition: CGFloat
    let endPosition: CGFloat
    let generation: UInt

    static let trackingPagesPerSecond: CGFloat = 4
    private static let firstControl = CGPoint(x: 0.27, y: 1)
    private static let secondControl = CGPoint(x: 0.18, y: 1)

    // The measured Arc curve stays unchanged. Interrupted continuations can
    // travel farther than one page and retain the same maximum speed.
    var duration: TimeInterval { CrestMotion.spaceSwipeTransition * max(1, abs(endPosition - startPosition)) }

    var timingFunction: CAMediaTimingFunction {
        CAMediaTimingFunction(
            controlPoints: Float(Self.firstControl.x), Float(Self.firstControl.y),
            Float(Self.secondControl.x), Float(Self.secondControl.y))
    }

    var animation: Animation { Self.animation(duration: duration) }

    static var standardAnimation: Animation { animation(duration: CrestMotion.spaceSwipeTransition) }

    private static func animation(duration: TimeInterval) -> Animation {
        .timingCurve(
            Double(Self.firstControl.x), Double(Self.firstControl.y),
            Double(Self.secondControl.x), Double(Self.secondControl.y), duration: duration)
    }

    /// Where the strip is `elapsed` seconds after the slide began, on the
    /// curve Core Animation draws it along.
    func position(after elapsed: TimeInterval) -> CGFloat {
        let progress = CGFloat(min(1, max(0, elapsed / duration)))
        return startPosition + (endPosition - startPosition) * Self.curve(at: progress)
    }

    /// The timing curve's output for the time fraction `x`, found by
    /// bisecting the curve's parameter.
    private static func curve(at x: CGFloat) -> CGFloat {
        func bezier(_ t: CGFloat, _ first: CGFloat, _ second: CGFloat) -> CGFloat {
            let u = 1 - t
            return 3 * u * u * t * first + 3 * u * t * t * second + t * t * t
        }
        var low: CGFloat = 0
        var high: CGFloat = 1
        for _ in 0..<32 {
            let t = (low + high) / 2
            if bezier(t, firstControl.x, secondControl.x) < x { low = t } else { high = t }
        }
        return bezier((low + high) / 2, firstControl.y, secondControl.y)
    }

    /// Include crossed boundaries so a reversal through a third Space blends
    /// its actual colors instead of interpolating straight between endpoints.
    var positions: [CGFloat] {
        let lower = min(startPosition, endPosition)
        let upper = max(startPosition, endPosition)
        let boundaries = (Int(lower.rounded(.down))...Int(upper.rounded(.up)))
            .map(CGFloat.init).filter { $0 > lower && $0 < upper }
        return [startPosition] + (endPosition > startPosition ? boundaries : boundaries.reversed()) + [endPosition]
    }

    func configure(_ animation: CAAnimation) {
        animation.duration = duration
        // Zero starts at the common rendering commit. A wall-clock start set
        // before SwiftUI layout can expire before the first frame is visible.
        animation.beginTime = 0
        animation.timingFunction = timingFunction
    }

    func animate(_ layer: CALayer, keyPath: String, values: [Any], followsSpaceBoundaries: Bool = true) {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        configure(animation)
        animation.values = values
        animation.keyTimes =
            followsSpaceBoundaries
            ? positions.map { NSNumber(value: Double(($0 - startPosition) / (endPosition - startPosition))) }
            : [0, 1]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(values.last, forKeyPath: keyPath)
        layer.add(animation, forKey: "spaceTransition.\(keyPath)")
        CATransaction.commit()
    }
}
