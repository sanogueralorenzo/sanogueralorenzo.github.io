import CoreGraphics

/// Shared measurements for the compact Space icon picker.
enum CrestSpaceIconPickerMetrics {
    static let segmentWidth: CGFloat = 40
    static let segmentHeight: CGFloat = 30
    static let cornerRadius: CGFloat = CrestRadius.compact
    static let trackPadding: CGFloat = 3
    static let trackFillOpacity = CrestOpacity.hover
    static let trackBorderOpacity = CrestOpacity.border
    static let selectionFillOpacity = 0.20
    static let overflowButtonWidth: CGFloat = 28
}

/// Styling changes with input size; selection, overflow and actions are shared.
struct CrestSpaceIconPickerStyle: Hashable, Sendable {
    // MARK: - Static Variables

    static let compact = CrestSpaceIconPickerStyle(
        name: "compact",
        height: CrestSpaceIconPickerMetrics.segmentHeight + 2 * CrestSpaceIconPickerMetrics.trackPadding,
        trackPadding: CrestSpaceIconPickerMetrics.trackPadding,
        fixedCornerRadius: CrestSpaceIconPickerMetrics.cornerRadius,
        minimumSegmentWidth: CrestSpaceIconPickerMetrics.segmentWidth, smallestSegment: .zero,
        overflowButtonWidth: CrestSpaceIconPickerMetrics.overflowButtonWidth, fillsSegments: false,
        trackFillOpacity: CrestSpaceIconPickerMetrics.trackFillOpacity,
        trackBorderOpacity: CrestSpaceIconPickerMetrics.trackBorderOpacity, tintsSelection: true,
        selectionFillOpacity: CrestSpaceIconPickerMetrics.selectionFillOpacity)
    static let touch = CrestSpaceIconPickerStyle(
        name: "touch", height: 48, trackPadding: CrestSpaceIconPickerMetrics.trackPadding, fixedCornerRadius: nil,
        minimumSegmentWidth: 52, smallestSegment: CGSize(width: 44, height: 42), overflowButtonWidth: 44,
        fillsSegments: true, trackFillOpacity: 0.08,
        trackBorderOpacity: 0, tintsSelection: false, selectionFillOpacity: 0.22)

    // MARK: - Variables

    let name: String
    private(set) var height: CGFloat

    /// The clearance between the track's edge and the segments inside it.
    private(set) var trackPadding: CGFloat

    /// The corner radius every part of the picker shares, or `nil` where each
    /// part is a capsule.
    private(set) var fixedCornerRadius: CGFloat?

    private(set) var minimumSegmentWidth: CGFloat

    /// The smallest a segment gets however small its crest is drawn. Touch
    /// keeps its full height and the width a finger needs; a pointer's
    /// segments shrink with their crests.
    let smallestSegment: CGSize

    let overflowButtonWidth: CGFloat

    /// Whether the segments widen to share the whole width the picker has.
    let fillsSegments: Bool

    let trackFillOpacity: Double
    let trackBorderOpacity: Double

    /// Whether the selected Space wears its own tint and outline, or a
    /// neutral fill.
    let tintsSelection: Bool

    let selectionFillOpacity: Double

    /// The height of one segment inside the track.
    var segmentHeight: CGFloat {
        height - 2 * trackPadding
    }

    // MARK: - Initializers

    private init(
        name: String, height: CGFloat, trackPadding: CGFloat, fixedCornerRadius: CGFloat?,
        minimumSegmentWidth: CGFloat, smallestSegment: CGSize, overflowButtonWidth: CGFloat, fillsSegments: Bool,
        trackFillOpacity: Double, trackBorderOpacity: Double, tintsSelection: Bool, selectionFillOpacity: Double
    ) {
        self.name = name
        self.height = height
        self.trackPadding = trackPadding
        self.fixedCornerRadius = fixedCornerRadius
        self.minimumSegmentWidth = minimumSegmentWidth
        self.smallestSegment = smallestSegment
        self.overflowButtonWidth = overflowButtonWidth
        self.fillsSegments = fillsSegments
        self.trackFillOpacity = trackFillOpacity
        self.trackBorderOpacity = trackBorderOpacity
        self.tintsSelection = tintsSelection
        self.selectionFillOpacity = selectionFillOpacity
    }

    // MARK: - Actions - Drawing

    /// The corner radius of a part of the picker `height` tall: the compact
    /// radius, or for touch half the height, so every part is a capsule.
    /// `CrestSpaceIconPickerShape` draws every part with it.
    func cornerRadius(forHeight height: CGFloat) -> CGFloat {
        fixedCornerRadius ?? height / 2
    }

    // MARK: - Actions - Sizing

    /// This style with segments sized for a crest drawn `scale` times its
    /// usual size, down to `smallestSegment`.
    ///
    /// The track's padding and corners follow the segment's height, so a
    /// smaller track keeps the shape of the full-size one rather than rounding
    /// off. Segments come out an even number of points each way and the
    /// padding a whole one, so a track of any size, and the crests centred in
    /// it, centre on the same point as the controls beside it.
    func scaled(by scale: CGFloat) -> CrestSpaceIconPickerStyle {
        let segmentHeight = max(smallestSegment.height, Self.evenPoints(self.segmentHeight * scale))
        let shape = segmentHeight / self.segmentHeight
        var style = self
        style.trackPadding = (trackPadding * shape).rounded()
        style.height = segmentHeight + 2 * style.trackPadding
        style.fixedCornerRadius = fixedCornerRadius.map { $0 * shape }
        style.minimumSegmentWidth = max(smallestSegment.width, Self.evenPoints(minimumSegmentWidth * scale))
        return style
    }

    /// `length` to the nearest even number of points.
    private static func evenPoints(_ length: CGFloat) -> CGFloat {
        2 * (length / 2).rounded()
    }

    /// How wide the track is with `spaceCount` Spaces side by side at their
    /// narrowest.
    func contentWidth(spaceCount: Int) -> CGFloat {
        guard spaceCount > 0 else { return 0 }
        return 2 * trackPadding + CGFloat(spaceCount) * minimumSegmentWidth
    }

    // MARK: - Actions - Identity

    static func == (lhs: CrestSpaceIconPickerStyle, rhs: CrestSpaceIconPickerStyle) -> Bool {
        lhs.name == rhs.name && lhs.height == rhs.height && lhs.minimumSegmentWidth == rhs.minimumSegmentWidth
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(height)
        hasher.combine(minimumSegmentWidth)
    }
}
