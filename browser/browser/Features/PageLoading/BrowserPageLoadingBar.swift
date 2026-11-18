import SwiftUI

struct BrowserPageLoadingBar: View {
    private struct Motion {
        private static let rampDuration: TimeInterval = 8
        private static let sweepDuration: TimeInterval = 0.14
        private static let fadeDelay: TimeInterval = 0.08
        private static let fadeDuration: TimeInterval = 0.12

        let width: Double
        let opacity: Double

        init(_ phase: BrowserPageLoading.Indicator, at time: TimeInterval) {
            switch phase {
            case .hidden:
                width = 0
                opacity = 0
            case .loading(let startedAt):
                width = Self.estimate(after: max(0, time - startedAt)).width
                opacity = 1
            case .revealed(let startedAt, let revealedAt):
                let elapsed = max(0, time - revealedAt)
                let estimate = Self.estimate(after: revealedAt - startedAt)
                let progress = min(1, elapsed / Self.sweepDuration)
                let remaining = 1 - estimate.width
                let tangent = min(Self.sweepDuration * estimate.velocity, 3 * remaining)
                let remainingTime = 1 - progress
                let fade = min(1, max(0, (elapsed - Self.fadeDelay) / Self.fadeDuration))
                let sweep = remaining * progress * progress * (3 - 2 * progress)
                    + tangent * progress * remainingTime * remainingTime
                width = min(1, estimate.width + sweep)
                opacity = 1 - UnitCurve.easeOut.value(at: fade)
            }
        }

        static func end(of phase: BrowserPageLoading.Indicator) -> TimeInterval {
            switch phase {
            case .hidden: 0
            case .loading(let startedAt): startedAt + rampDuration
            case .revealed(_, let revealedAt): revealedAt + fadeDelay + fadeDuration
            }
        }

        private static func estimate(after elapsed: TimeInterval) -> (width: Double, velocity: Double) {
            let fastRate = 3.9
            let slowRate = 0.42
            let fastRemainder = 0.72 * exp(-fastRate * elapsed)
            let slowRemainder = 0.28 * exp(-slowRate * elapsed)
            let width = 1 - fastRemainder - slowRemainder
            if width >= 0.99 { return (0.99, 0) }
            return (width, fastRate * fastRemainder + slowRate * slowRemainder)
        }
    }

    let indicator: BrowserPageLoading.Indicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settledIndicator = BrowserPageLoading.Indicator.hidden

    private var reducedMotionWidth: Double {
        if case .loading = indicator { return 0.25 }
        return 0
    }

    var body: some View {
        let staticWidth = reduceMotion ? reducedMotionWidth : nil
        let phase = reduceMotion ? .hidden : indicator
        let end = Motion.end(of: phase)
        TimelineView(.animation(paused: settledIndicator == phase || end <= ProcessInfo.processInfo.systemUptime)) { _ in
            let motion = Motion(phase, at: ProcessInfo.processInfo.systemUptime)
            Rectangle().fill(.primary)
                .frame(height: 2)
                .scaleEffect(x: staticWidth ?? motion.width, y: 1, anchor: .leading)
                .opacity(staticWidth == nil ? motion.opacity : 1)
        }
        .task(id: phase) {
            let remaining = end - ProcessInfo.processInfo.systemUptime
            if remaining > 0 {
                do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            }
            if !Task.isCancelled { settledIndicator = phase }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
