import SwiftUI
import UIKit

/// Steps a page back or forward when a finger swipes in from the page's own
/// edge, as Safari does, through the core's history. WebKit's own swipe stays
/// off because it would walk WebKit's list instead.
///
/// The page follows the finger a little and the gap it opens shows which way
/// the swipe goes. Letting go once the chevron turns primary, or flicking
/// inward, takes the step; anything shorter settles back.
///
/// Only a swipe that starts within a finger's width of the edge counts. While
/// one is deciding, the page's own pans and the sheet's dismiss pan wait for
/// it, so a carousel or map running to the edge does not take it first. Where a
/// collapsed sidebar's strip covers the top and bottom of the same edge, the
/// strip answers there and the swipe starts from the middle.
@MainActor
final class MobileHistorySwipe: NSObject, UIGestureRecognizerDelegate {
    // MARK: - Static Variables

    /// How far in from the page's edge a swipe can start.
    static let edgeBandWidth: CGFloat = 24
    /// How far a finger travels in before letting go takes the step.
    static let commitDistance: CGFloat = 96
    /// How fast an inward flick takes the step from a shorter swipe.
    static let commitVelocity: CGFloat = 800
    /// How much of the finger's travel the page follows up to the commit
    /// distance, and how much past it.
    static let followRatio: CGFloat = 0.6
    static let overshootRatio: CGFloat = 0.12
    /// How far the indicator keeps from the top and bottom of the page.
    static let indicatorVerticalInset: CGFloat = 64

    // MARK: - Variables

    /// The page a swipe steps, refreshed by the representable so a reused host
    /// never steps the page it showed before.
    weak var page: MobileBrowserPage?

    private weak var host: MobileBrowserWebHostView?
    /// The direction of the touch being tracked, chosen by the edge it landed
    /// near; nil when the touch is not a history swipe.
    private var direction: MobileHistorySwipeDirection?
    /// Whether the page is following a swipe under way.
    private var isFollowing = false
    private var isArmed = false
    private var indicatorY: CGFloat = 0

    private lazy var recognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = self
        return recognizer
    }()

    private lazy var indicator: UIView & UIContentView = {
        let indicator = indicatorConfiguration(systemImage: "chevron.backward", isArmed: false).makeContentView()
        indicator.isUserInteractionEnabled = false
        indicator.alpha = 0
        return indicator
    }()

    // MARK: - Actions - Installation

    /// Listens for history swipes on `host`, the view that shows the page.
    func install(on host: MobileBrowserWebHostView) {
        guard recognizer.view == nil else { return }
        self.host = host
        host.addGestureRecognizer(recognizer)
    }

    // MARK: - Actions - Gesture

    @objc private func pan(_ recognizer: UIPanGestureRecognizer) {
        guard let host, direction != nil else { return }
        let translation = recognizer.translation(in: host)
        switch recognizer.state {
        case .began:
            begin(at: recognizer.location(in: host), translation: translation, in: host)
        case .changed:
            move(translation: translation, in: host)
        case .ended:
            finish(translation: translation, velocity: recognizer.velocity(in: host), in: host)
        default:
            settle(in: host)
        }
    }

    // MARK: - Actions - Swipes beside the page

    /// Follows a swipe that began on the frame beside the page, in from
    /// `direction`'s edge, at `point` in the window. False where the page has
    /// no step that way or a swipe on it is already under way.
    func beginBesidePage(from direction: MobileHistorySwipeDirection, at point: CGPoint) -> Bool {
        guard let host, let page, host.window != nil, recognizer.state == .possible, !isFollowing,
            direction.isAvailable(on: page)
        else { return false }
        self.direction = direction
        begin(at: host.convert(point, from: nil), translation: .zero, in: host)
        return true
    }

    /// Moves a swipe begun beside the page `translation` points from where it began.
    func moveBesidePage(translation: CGPoint) {
        guard let host, isFollowing, recognizer.state == .possible else { return }
        move(translation: translation, in: host)
    }

    /// Ends a swipe begun beside the page, taking the step if it went far or
    /// fast enough.
    func endBesidePage(translation: CGPoint, velocity: CGPoint) {
        guard let host, isFollowing, recognizer.state == .possible else { return }
        finish(translation: translation, velocity: velocity, in: host)
    }

    // MARK: - Actions - Following

    private func begin(at point: CGPoint, translation: CGPoint, in host: MobileBrowserWebHostView) {
        guard let direction else { return }
        let pageFrame = host.pageFrame
        indicatorY = min(
            max(point.y, pageFrame.minY + Self.indicatorVerticalInset),
            pageFrame.maxY - Self.indicatorVerticalInset
        )
        isFollowing = true
        setArmed(false, direction: direction)
        host.addSubview(indicator)
        move(translation: translation, in: host)
    }

    private func move(translation: CGPoint, in host: MobileBrowserWebHostView) {
        guard let direction else { return }
        let inward = direction.inwardDistance(
            of: translation, layoutDirection: host.effectiveUserInterfaceLayoutDirection)
        follow(inward: inward, direction: direction, in: host)
    }

    private func finish(translation: CGPoint, velocity: CGPoint, in host: MobileBrowserWebHostView) {
        guard let direction else { return }
        let layoutDirection = host.effectiveUserInterfaceLayoutDirection
        let inward = direction.inwardDistance(of: translation, layoutDirection: layoutDirection)
        let inwardVelocity = direction.inwardDistance(of: velocity, layoutDirection: layoutDirection)
        let commits = inward >= Self.commitDistance || (inward > 0 && inwardVelocity >= Self.commitVelocity)
        if commits, let page { direction.step(on: page) }
        settle(in: host)
    }

    /// Moves the page and the indicator with a finger `inward` points in from
    /// `direction`'s edge.
    private func follow(inward: CGFloat, direction: MobileHistorySwipeDirection, in host: MobileBrowserWebHostView) {
        let layoutDirection = host.effectiveUserInterfaceLayoutDirection
        let travel = max(inward, 0)
        let progress = min(travel / Self.commitDistance, 1)
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let shift =
            reduceMotion
            ? 0
            : min(travel, Self.commitDistance) * Self.followRatio
                + max(travel - Self.commitDistance, 0) * Self.overshootRatio
        let sign = direction.inwardSign(in: layoutDirection)
        host.shiftPage(by: shift * sign)
        if isArmed != (progress >= 1) { setArmed(progress >= 1, direction: direction) }

        // The indicator rides in the gap the page leaves, sliding in from
        // beyond the edge; without motion it waits just inside the edge.
        let size = CrestLayout.minimumHitTarget
        let edgeX = direction.edgeX(of: host.pageFrame, layoutDirection: layoutDirection)
        let offset = reduceMotion ? size / 2 + CrestSpacing.small : shift - size / 2 - CrestSpacing.small
        indicator.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        indicator.center = CGPoint(x: edgeX + offset * sign, y: indicatorY)
        indicator.alpha = progress
        host.bringSubviewToFront(indicator)
    }

    /// Puts the page back in place and lets the indicator go, whether or not
    /// the swipe took a step.
    private func settle(in host: MobileBrowserWebHostView) {
        direction = nil
        isFollowing = false
        let indicator = indicator
        let changes = {
            host.shiftPage(by: 0)
            indicator.alpha = 0
        }
        // A swipe that began while this one settled keeps the page and the
        // indicator.
        let completion = { [weak self] in
            guard self?.isFollowing != true else { return }
            host.endPageShift()
            indicator.removeFromSuperview()
        }
        if let animation = CrestMotion.spaceSwipe.unlessReducingMotion(UIAccessibility.isReduceMotionEnabled) {
            UIView.animate(animation, changes: changes, completion: completion)
        } else {
            changes()
            completion()
        }
    }

    private func setArmed(_ isArmed: Bool, direction: MobileHistorySwipeDirection) {
        self.isArmed = isArmed
        indicator.configuration = indicatorConfiguration(systemImage: direction.systemImage, isArmed: isArmed)
    }

    private func indicatorConfiguration(systemImage: String, isArmed: Bool) -> some UIContentConfiguration {
        UIHostingConfiguration {
            MobileHistorySwipeIndicator(systemImage: systemImage, isArmed: isArmed)
        }
        .margins(.all, 0)
    }

    // MARK: - Actions - Recognition

    /// Tracks a touch only when it lands near an edge the page can step from.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // A swipe begun beside the page keeps its direction while it runs.
        guard let host, let page, recognizer.state == .possible, !isFollowing else { return false }
        let landed = MobileHistorySwipeDirection.starting(
            at: touch.location(in: host),
            in: host.pageFrame,
            within: Self.edgeBandWidth,
            layoutDirection: host.effectiveUserInterfaceLayoutDirection
        )
        direction = landed.flatMap { $0.isAvailable(on: page) ? $0 : nil }
        return direction != nil
    }

    /// Begins only for a mostly horizontal move in from the edge. The pan has
    /// no translation yet when it asks, so its velocity says which way it goes.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let host, let direction else { return false }
        let velocity = recognizer.velocity(in: host)
        let inward = direction.inwardDistance(of: velocity, layoutDirection: host.effectiveUserInterfaceLayoutDirection)
        let begins = inward > abs(velocity.y)
        if !begins { self.direction = nil }
        return begins
    }

    /// Other pans wait while a touch near the edge decides whether it is a
    /// history swipe; one that lands anywhere else never involves this one.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        direction != nil && otherGestureRecognizer is UIPanGestureRecognizer
    }
}
