import CoreGraphics

/// How the sidebar's Space switcher sizes its Spaces on this device: fitted to
/// the strip it stands in, or at the scale the person set.
///
/// Fitting takes the largest step of `fittingRange` at which every Space lies
/// side by side across the strip, and never draws them larger than usual.
/// Below the floor the strip scrolls with its overflow arrows instead of
/// shrinking further. Fitting moves in the slider's own steps, so a live
/// sidebar resize redraws the crests only as the strip crosses one, not on
/// every frame.
struct BrowserSpaceIconSizing: Hashable, Sendable {
    // MARK: - Static Variables

    static let automatic = BrowserSpaceIconSizing(name: "automatic", fitsStrip: true)
    static let manual = BrowserSpaceIconSizing(name: "manual", fitsStrip: false)
    static let all = [automatic, manual]
    static let standard = automatic

    /// The scales a person can set, as fractions of the default size.
    static let scaleRange: ClosedRange<Double> = 0.3...1.5

    /// The scales fitting chooses between, from its floor up to the usual
    /// size.
    static let fittingRange: ClosedRange<Double> = 0.3...1

    /// The step the slider and fitting both move in.
    static let scaleStep = 0.05

    /// `fittingRange` in steps, largest first, counted in whole percent so
    /// every step lands exactly.
    private static let fittingScales: [CGFloat] = {
        let percent = { (scale: Double) in Int((scale * 100).rounded()) }
        return stride(
            from: percent(fittingRange.upperBound), through: percent(fittingRange.lowerBound), by: -percent(scaleStep)
        ).map { CGFloat($0) / 100 }
    }()

    // MARK: - Variables

    /// The persisted spelling.
    let name: String

    /// Whether the switcher works its scale out from the strip's width,
    /// rather than keeping the one the person set.
    let fitsStrip: Bool

    // MARK: - Initializers

    private init(name: String, fitsStrip: Bool) {
        self.name = name
        self.fitsStrip = fitsStrip
    }

    // MARK: - Actions - Sizing

    /// The scale `spaceCount` Spaces in `style` are drawn at across a strip
    /// `width` wide, when the person set `chosen`.
    ///
    /// When even the floor is too wide, fitting keeps the largest scale that
    /// is still the narrowest: a touch segment stops narrowing at its target
    /// size, so shrinking its crest any further would win no room.
    func scale(chosen: Double, spaceCount: Int, style: CrestSpaceIconPickerStyle, width: CGFloat) -> CGFloat {
        guard fitsStrip else { return Self.clamped(chosen) }
        let widths = Self.fittingScales.map { ($0, style.scaled(by: $0).contentWidth(spaceCount: spaceCount)) }
        if let fitting = widths.first(where: { $0.1 <= width }) { return fitting.0 }
        return widths.min { $0.1 < $1.1 }?.0 ?? 1
    }

    /// The largest scale this sizing draws at, which is the room the strip
    /// keeps for its track.
    func largestScale(chosen: Double) -> CGFloat {
        fitsStrip ? CGFloat(Self.fittingRange.upperBound) : Self.clamped(chosen)
    }

    /// A stored scale held to `scaleRange`, or the default size when it is not
    /// a number.
    static func clamped(_ value: Double) -> CGFloat {
        value.isFinite ? CGFloat(min(max(value, scaleRange.lowerBound), scaleRange.upperBound)) : 1
    }

    // MARK: - Actions - Lookup

    static func named(_ name: String?) -> BrowserSpaceIconSizing? {
        all.first { $0.name == name }
    }
}

// MARK: - Hashable

extension BrowserSpaceIconSizing {
    static func == (lhs: BrowserSpaceIconSizing, rhs: BrowserSpaceIconSizing) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
