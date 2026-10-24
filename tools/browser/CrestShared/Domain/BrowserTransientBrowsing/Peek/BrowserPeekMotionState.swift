import Foundation

/// Position and velocity use the source window's normalized content coordinates.
struct BrowserPeekMotionState: Equatable, Sendable {
    static let initialScale = 0.08

    var origin: CGPoint
    var location: CGPoint
    var velocity: CGSize = .zero
    var scale: Double
    var scaleVelocity: Double = 0
    var releasedAt: Date?
    var returnsToSource = false

    /// Clicks settle from the link without pull velocity or an activation threshold.
    static func opening(from source: BrowserPeekSourcePresentation?) -> Self {
        let source = BrowserPeekSourcePresentation.resolved(source)
        let origin = CGPoint(x: source.normalizedTouchX, y: source.normalizedTouchY)
        return Self(origin: origin, location: origin, scale: initialScale, releasedAt: Date())
    }
}

/// Computes the shared motion state from normalized pointer or touch samples.
struct BrowserPeekPullSession {
    private enum Motion {
        static let minimumSampleInterval: TimeInterval = 0.001
        static let velocityExpirationInterval: TimeInterval = 0.12
        static let velocitySmoothingInterval: TimeInterval = 0.035
        static let maximumScaleGrowth = 0.72
        static let scaleResponseDistance = 180.0
        static let activationRadius: CGFloat = 28
        static let cancellationRadialVelocity: CGFloat = -12
    }

    private(set) var state: BrowserPeekMotionState
    private var previousTime: TimeInterval

    init(origin: CGPoint, location: CGPoint, size: CGSize, time: TimeInterval) {
        state = BrowserPeekMotionState(
            origin: origin, location: location,
            scale: Self.scale(at: location, origin: origin, size: size))
        previousTime = time
    }

    mutating func move(to point: CGPoint, size: CGSize, time: TimeInterval) {
        let dt = time - previousTime
        let nextScale = Self.scale(at: point, origin: state.origin, size: size)
        if dt > Motion.minimumSampleInterval {
            if dt > Motion.velocityExpirationInterval {
                state.velocity = .zero
                state.scaleVelocity = 0
            } else {
                let weight = min(1, dt / Motion.velocitySmoothingInterval)
                state.velocity.width += ((point.x - state.location.x) / dt - state.velocity.width) * weight
                state.velocity.height += ((point.y - state.location.y) / dt - state.velocity.height) * weight
                state.scaleVelocity += ((nextScale - state.scale) / dt - state.scaleVelocity) * weight
            }
        }
        state.location = point
        state.scale = nextScale
        previousTime = time
    }

    mutating func release(size: CGSize, at date: Date = .now) {
        state.releasedAt = date
        state.returnsToSource = !Self.opensPeek(
            translation: CGSize(
                width: (state.location.x - state.origin.x) * size.width,
                height: (state.location.y - state.origin.y) * size.height),
            velocity: CGSize(width: state.velocity.width * size.width, height: state.velocity.height * size.height))
    }

    /// Whether a pull released with `translation` and `velocity`, in
    /// points, opens its Peek rather than returning to the link.
    static func opensPeek(translation: CGSize, velocity: CGSize) -> Bool {
        let distance = hypot(translation.width, translation.height)
        guard distance >= Motion.activationRadius else { return false }
        let radialVelocity = (translation.width * velocity.width + translation.height * velocity.height) / distance
        // A resting hand commits outside the radius; a pull back cancels.
        return radialVelocity >= Motion.cancellationRadialVelocity
    }

    private static func scale(at point: CGPoint, origin: CGPoint, size: CGSize) -> Double {
        let distance = hypot((point.x - origin.x) * size.width, (point.y - origin.y) * size.height)
        return BrowserPeekMotionState.initialScale
            + Motion.maximumScaleGrowth * (1 - exp(-distance / Motion.scaleResponseDistance))
    }
}
