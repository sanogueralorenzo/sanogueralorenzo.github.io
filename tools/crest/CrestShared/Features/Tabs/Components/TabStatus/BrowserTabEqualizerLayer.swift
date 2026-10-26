import Foundation
import QuartzCore

/// Bars along the bottom of a tab while its page plays sound, drawn as one
/// shape. Following its engine's measure of the sound, each bar shows a
/// frequency band, lowest on the leading edge, and the shape eases to each new
/// measure in the render server. Without a measure the bars step through
/// heights of their own, over and over, at a low frame rate. Either way the
/// app commits one animation of one layer at a time and does no work between
/// them. A layer that holds still draws every bar at rest.
final class BrowserTabEqualizerLayer: CAShapeLayer {
    // MARK: - Static Variables

    /// The bars across the tab, one per band the engine measures. They stand
    /// side by side with no gap and share the width, so together they read as
    /// one band across the tab.
    static let barCount = 24

    /// The share of the tab's height a bar always keeps, and how much more it
    /// reaches at its peak.
    static let restingHeight: CGFloat = 0.12
    static let peakHeight: CGFloat = 0.6

    /// How many heights the bars step through on their own before repeating,
    /// and how long a round takes.
    static let keyframeCount = 8
    static let round: CFTimeInterval = 2.4

    /// How long the bars take to reach a new measure: about the time until
    /// the next one, so they move continuously.
    static let measureEasing: CFTimeInterval = 1.0 / 15

    /// The most often the render server redraws moving bars.
    static let frameRate = CAFrameRateRange(minimum: 8, maximum: 30, preferred: 30)

    static let animationKey = "level"

    #if os(macOS)
        /// AppKit's layer coordinates run bottom-up, so the bars stand on the
        /// lowest coordinate.
        static let growsDown = false
    #else
        /// UIKit's layer coordinates run top-down, so the bars stand on the
        /// highest coordinate.
        static let growsDown = true
    #endif

    // MARK: - Variables

    var barColor: CGColor? {
        didSet {
            guard barColor != oldValue else { return }
            fillColor = barColor
        }
    }

    /// Whether the bars move. Reduce Motion holds them still.
    var isMoving = true {
        didSet {
            guard isMoving != oldValue else { return }
            redraw()
        }
    }

    private var drawnSize: CGSize = .zero

    /// The measure the bars follow, while they follow one, and the watch that
    /// keeps the engine measuring.
    private weak var spectrum: BrowserAudioSpectrumFeed?
    private var watch: UUID?

    /// The last measure, one level from 0 to 255 per band, lowest first.
    private var measured = Data()

    /// The share of a bar's full height it keeps at rest.
    private static var floor: CGFloat { restingHeight / (restingHeight + peakHeight) }

    // MARK: - Initializers

    override init() {
        super.init()
        masksToBounds = true
        fillColor = nil
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - Actions - Measures

    /// Follows `feed`, the engine's measure of the page's sound, or moves on
    /// its own without one. Following starts the engine measuring; letting go
    /// stops it once nothing else watches.
    @MainActor func follow(_ feed: BrowserAudioSpectrumFeed?) {
        guard feed !== spectrum else { return }
        if let spectrum, let watch { spectrum.unwatch(watch) }
        spectrum = feed
        watch = feed?.watch { [weak self] bands in self?.show(bands) }
        measured = Data()
        redraw()
    }

    /// Eases the bars from the last measure to `bands`. Each ease lasts about
    /// until the next measure, so the last one has all but finished.
    private func show(_ bands: Data) {
        measured = bands
        let target = path(heights: measuredHeights())
        let ease = CABasicAnimation(keyPath: "path")
        ease.fromValue = path
        ease.toValue = target
        ease.duration = Self.measureEasing
        ease.preferredFrameRateRange = Self.frameRate
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        add(ease, forKey: Self.animationKey)
        path = target
        CATransaction.commit()
    }

    /// Each bar's share of its full height from the last measure, each bar
    /// between two bands taking from both.
    private func measuredHeights() -> [CGFloat] {
        (0..<Self.barCount).map { index in
            guard !measured.isEmpty else { return Self.floor }
            let place = CGFloat(index) / CGFloat(Self.barCount - 1) * CGFloat(measured.count - 1)
            let lower = min(Int(place), measured.count - 1)
            let upper = min(lower + 1, measured.count - 1)
            let low = CGFloat(measured[measured.startIndex + lower])
            let high = CGFloat(measured[measured.startIndex + upper])
            return Self.floor + (1 - Self.floor) * (low + (high - low) * (place - CGFloat(lower))) / 255
        }
    }

    // MARK: - Actions - Layout

    override func layoutSublayers() {
        super.layoutSublayers()
        guard bounds.size != drawnSize else { return }
        redraw()
    }

    /// Draws the bars for the layer's size: following the measure, moving on
    /// their own, or at rest.
    private func redraw() {
        drawnSize = bounds.size
        removeAnimation(forKey: Self.animationKey)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if spectrum != nil || !isMoving {
            path = path(heights: measuredHeights())
        } else {
            let rounds = (0...Self.keyframeCount).map { step in
                path(heights: (0..<Self.barCount).map { Self.height(of: $0, at: step % Self.keyframeCount) })
            }
            let motion = CAKeyframeAnimation(keyPath: "path")
            motion.values = rounds
            motion.duration = Self.round
            motion.repeatCount = .infinity
            motion.isRemovedOnCompletion = false
            motion.preferredFrameRateRange = Self.frameRate
            add(motion, forKey: Self.animationKey)
            path = rounds[0]
        }
        CATransaction.commit()
    }

    /// One rectangle per bar, side by side across the width, each standing on
    /// the bottom edge at its share of the full height. Every path has the
    /// same rectangles, so the render server eases between them.
    private func path(heights: [CGFloat]) -> CGPath {
        let path = CGMutablePath()
        guard bounds.width > 0, bounds.height > 0 else { return path }
        let width = bounds.width / CGFloat(Self.barCount)
        let fullHeight = bounds.height * (Self.restingHeight + Self.peakHeight)
        for (index, share) in heights.enumerated() {
            let height = fullHeight * share
            let foot = Self.growsDown ? bounds.height - height : 0
            path.addRect(CGRect(x: CGFloat(index) * width, y: foot, width: width, height: height))
        }
        return path
    }

    // MARK: - Actions - Motion

    /// Bar `index`'s share of its full height at step `step` of the bars' own
    /// round: a fixed scatter of its own, so neighbours never move together.
    private static func height(of index: Int, at step: Int) -> CGFloat {
        var state = UInt64(truncatingIfNeeded: (index &* 2_654_435_761) ^ (step &* 40_503) &+ 97)
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let unit = CGFloat(state >> 40) / CGFloat(1 << 24)
        return floor + (1 - floor) * unit
    }
}
