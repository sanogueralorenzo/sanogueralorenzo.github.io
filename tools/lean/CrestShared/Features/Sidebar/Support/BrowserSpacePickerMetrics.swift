import CoreGraphics

struct BrowserSpacePickerMetrics: Equatable, Sendable {
    // MARK: - Static Variables

    /// A pointer shell: a small color dot inside the titlebar capsule.
    static let pointer = BrowserSpacePickerMetrics(
        iconSize: 12,
        iconPadding: 0
    )

    /// A touch shell: a larger crest with clearance around it, drawn in the
    /// square a finger aims at.
    static let touch = BrowserSpacePickerMetrics(
        iconSize: 20,
        iconPadding: 4
    )

    // MARK: - Variables

    /// The square the Space's crest is drawn into.
    let iconSize: CGFloat

    /// The clearance around the crest inside its segment.
    let iconPadding: CGFloat

    // MARK: - Actions - Sizing

    /// These metrics with the crest, its badge and its clearance drawn `scale`
    /// times their usual size, in whole points. The crest stays an even number
    /// of points, as its segment is, so it centres on a whole point.
    func scaled(by scale: CGFloat) -> BrowserSpacePickerMetrics {
        BrowserSpacePickerMetrics(
            iconSize: 2 * (iconSize * scale / 2).rounded(),
            iconPadding: (iconPadding * scale).rounded()
        )
    }
}
