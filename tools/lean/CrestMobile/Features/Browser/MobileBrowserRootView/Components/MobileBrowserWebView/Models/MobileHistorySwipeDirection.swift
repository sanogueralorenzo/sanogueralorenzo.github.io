import UIKit

/// Which way a swipe in from a page's edge steps through its history: in from
/// the leading edge goes back, in from the trailing edge goes forward, as in
/// Safari. Each step goes through the core's history, as the toolbar's do.
@MainActor
struct MobileHistorySwipeDirection {
    // MARK: - Static Variables

    static let back = MobileHistorySwipeDirection(
        startsAtLeadingEdge: true,
        systemImage: "chevron.backward",
        isAvailable: { $0.live.canGoBack },
        step: { $0.goBack() }
    )

    static let forward = MobileHistorySwipeDirection(
        startsAtLeadingEdge: false,
        systemImage: "chevron.forward",
        isAvailable: { $0.live.canGoForward },
        step: { $0.goForward() }
    )

    static let all = [back, forward]

    // MARK: - Variables

    /// Whether the swipe starts at the edge text begins from.
    let startsAtLeadingEdge: Bool
    /// The chevron shown beside the page while the swipe is under way.
    let systemImage: String
    private let availability: (MobileBrowserPage) -> Bool
    private let takeStep: (MobileBrowserPage) -> Void

    // MARK: - Initializers

    private init(
        startsAtLeadingEdge: Bool,
        systemImage: String,
        isAvailable: @escaping (MobileBrowserPage) -> Bool,
        step: @escaping (MobileBrowserPage) -> Void
    ) {
        self.startsAtLeadingEdge = startsAtLeadingEdge
        self.systemImage = systemImage
        availability = isAvailable
        takeStep = step
    }

    // MARK: - Actions - Geometry

    /// The direction whose edge `point` is within `bandWidth` of, if any.
    static func starting(
        at point: CGPoint,
        in bounds: CGRect,
        within bandWidth: CGFloat,
        layoutDirection: UIUserInterfaceLayoutDirection
    ) -> MobileHistorySwipeDirection? {
        all.first { direction in
            (0..<bandWidth).contains(direction.distance(of: point, from: bounds, layoutDirection: layoutDirection))
        }
    }

    /// 1 where this direction's edge is the left one on screen, -1 where it is
    /// the right one: the way a finger moves to come in from it.
    func inwardSign(in layoutDirection: UIUserInterfaceLayoutDirection) -> CGFloat {
        startsAtLeadingEdge == (layoutDirection == .leftToRight) ? 1 : -1
    }

    /// How far `translation` carries a finger in from this direction's edge;
    /// negative when it heads back out.
    func inwardDistance(of translation: CGPoint, layoutDirection: UIUserInterfaceLayoutDirection) -> CGFloat {
        translation.x * inwardSign(in: layoutDirection)
    }

    /// The x of this direction's edge of `bounds`.
    func edgeX(of bounds: CGRect, layoutDirection: UIUserInterfaceLayoutDirection) -> CGFloat {
        inwardSign(in: layoutDirection) > 0 ? bounds.minX : bounds.maxX
    }

    private func distance(
        of point: CGPoint,
        from bounds: CGRect,
        layoutDirection: UIUserInterfaceLayoutDirection
    ) -> CGFloat {
        (point.x - edgeX(of: bounds, layoutDirection: layoutDirection)) * inwardSign(in: layoutDirection)
    }

    // MARK: - Actions - History

    /// Whether `page` has an entry this way in the core's history.
    func isAvailable(on page: MobileBrowserPage) -> Bool {
        availability(page)
    }

    /// Takes the step on `page`.
    func step(on page: MobileBrowserPage) {
        takeStep(page)
    }
}
