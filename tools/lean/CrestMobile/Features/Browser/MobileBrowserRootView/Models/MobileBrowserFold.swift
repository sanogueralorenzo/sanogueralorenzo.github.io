import SwiftUI

/// The fold of a display held partly closed like a book, as iPhone Duo can be,
/// where it divides the window into two sides.
///
/// The sidebar and the pages keep to one side or the other while it lasts. The
/// system says where the fold is and how much room around it to leave; nothing
/// laid out around it is saved, so opening the device flat brings back the
/// layout the person chose.
struct MobileBrowserFold: Equatable, Sendable {
    // MARK: - Variables

    /// The fold with the clearance the system keeps around it, in the global
    /// coordinate space.
    let frame: CGRect

    // MARK: - Actions - Reading

    /// The fold dividing the view `proxy` measures into a left and a right
    /// side, or nil while the display is flat, has no fold, or folds across.
    static func dividing(_ proxy: GeometryProxy) -> MobileBrowserFold? {
        #if canImport(SwiftUICore, _version: 8.0.85)
            if #available(iOS 27.1, *) {
                let origin = proxy.frame(in: .global).origin
                return
                    proxy
                    .reservedRegions(kind: .division, layoutDirectionBehavior: .fixed)
                    .first { $0.isActive && $0.frame.height > $0.frame.width }
                    .map { MobileBrowserFold(frame: $0.frame.offsetBy(dx: origin.x, dy: origin.y)) }
            }
        #endif
        return nil
    }

    /// Whether the display `proxy` measures can fold at all, flat or not.
    static func isFoldable(_ proxy: GeometryProxy) -> Bool {
        #if canImport(SwiftUICore, _version: 8.0.85)
            if #available(iOS 27.1, *) {
                return !proxy.reservedRegions(kind: .division, options: .includeInactive).isEmpty
            }
        #endif
        return false
    }

    // MARK: - Actions - Layout

    /// Where the fold crosses `container`, a global frame, measured from the
    /// container's leading edge in `direction`.
    func span(
        across container: CGRect,
        direction: LayoutDirection
    ) -> ClosedRange<CGFloat> {
        let lower = frame.minX - container.minX
        let upper = frame.maxX - container.minX
        guard direction == .rightToLeft else { return lower...upper }
        return (container.width - upper)...(container.width - lower)
    }

    /// Column fractions for `memberCount` pages across `container` that put
    /// the boundary nearest the middle in the fold: as many pages before it as
    /// after, the extra one going first.
    func columnFractions(
        memberCount: Int,
        across container: CGRect,
        direction: LayoutDirection,
        gap: CGFloat
    ) -> [Double]? {
        guard memberCount > 1 else { return nil }
        let middle = span(across: container, direction: direction)
        let foldCenter = (middle.lowerBound + middle.upperBound) / 2
        let available = container.width - gap * CGFloat(memberCount - 1)
        guard available > 0, foldCenter > 0, foldCenter < container.width else { return nil }

        let leadingCount = (memberCount + 1) / 2
        let trailingCount = memberCount - leadingCount
        let leadingWidth = foldCenter - gap / 2 - gap * CGFloat(leadingCount - 1)
        let trailingWidth = available - leadingWidth
        guard leadingWidth > 0, trailingWidth > 0 else { return nil }

        let leading = Array(
            repeating: Double(leadingWidth / CGFloat(leadingCount) / available),
            count: leadingCount
        )
        let trailing = Array(
            repeating: Double(trailingWidth / CGFloat(trailingCount) / available),
            count: trailingCount
        )
        return leading + trailing
    }
}

extension EnvironmentValues {
    /// The fold dividing the window, while there is one.
    @Entry var mobileBrowserFold: MobileBrowserFold?
}
