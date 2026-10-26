import SwiftUI

/// The address bar's swipe through the tabs of the Space a window shows, as
/// the page area and the bar draw it.
///
/// The core decides where a swipe goes (`BrowserStore.swipeNeighbors`) and
/// shows the tab it lands on; this carries only the motion between the two,
/// the way a Space switch carries it: the page follows the finger, a release
/// settles on the Space pager's curve, and the bar keeps the tab it shows
/// until the move lands. Past either end of the Space the page leans a little
/// and springs back, and the bar shakes, so a swipe never reaches another
/// Space.
@MainActor @Observable
final class MobileTabSwipe {
    // MARK: - Types

    /// What the swipe is doing.
    enum Phase: Equatable {
        /// Nothing moves, and the page area shows the shown tab alone.
        case idle
        /// A finger is moving the page.
        case tracking
        /// The page is settling where a release or a step sent it.
        case settling
    }

    // MARK: - Static Variables

    /// How far a drag travels before it is decided to be a swipe or not.
    static let recognitionDistance: CGFloat = 12
    /// How much more horizontal than vertical a drag has to be to be a swipe,
    /// the share a Space swipe asks for.
    static let horizontalDominance: CGFloat = 1.35
    /// How far, in page widths, a release's predicted end has to reach to
    /// carry on to the neighbour.
    static let landingTravel: CGFloat = 0.5
    /// The furthest, in page widths, the page leans past an end of the Space.
    static let boundaryReach: CGFloat = 0.12

    // MARK: - Variables

    private(set) var phase = Phase.idle
    /// How far the page has moved toward the next tab, in page widths:
    /// positive on toward the next tab, negative back toward the previous.
    private(set) var travel: CGFloat = 0
    /// The tabs either side of the shown one, as the core last answered: when
    /// the shown tab changed, and again as a swipe begins. The page area keeps
    /// the ones with pages in memory ready beside it while idle, as the Space
    /// pager keeps its neighbours, so a swipe slides in a page already drawn.
    private(set) var neighbors = SwipeNeighborTabs(previousTabID: nil, nextTabID: nil)
    /// Counts the swipes that met an end of the Space, each of which shakes
    /// the bar.
    private(set) var boundaryHits = 0
    /// How opaque the shown tab's page is: whole, except as a page Reduce
    /// Motion swapped in without a slide fades in.
    private(set) var shownOpacity: Double = 1
    /// The tab the last swipe landed on, which keeps the look it slid in
    /// with until its page has drawn, rather than show a bare page area.
    private(set) var landedTabID: UUID?
    /// The page area's width, which turns finger travel into pages.
    @ObservationIgnored var pageWidth: CGFloat = 0
    /// The drag on the bar was decided to be no swipe, so it never becomes one.
    @ObservationIgnored private var declinedDrag = false
    /// The settle in flight, so a completion can tell itself from a later one.
    @ObservationIgnored private var generation: UInt = 0
    /// The tab the settle in flight lands on, which a new swipe lands on at
    /// once instead, and how it shows it.
    @ObservationIgnored private var landingTabID: UUID?
    @ObservationIgnored private var land: ((UUID) -> Void)?
    /// How the swipe in flight asks the core for the tabs either side, which
    /// it asks again for the tab it lands on.
    @ObservationIgnored private var askNeighbors: (() -> SwipeNeighborTabs)?

    // MARK: - Actions - Gesture

    /// Follows a drag on the bar that has travelled `translation`. A drag
    /// that is not first of all horizontal is never a swipe, which leaves it
    /// to the bar's upward reveal; one that is asks the core where it may go.
    func track(
        _ translation: CGSize, layoutDirection: LayoutDirection, reduceMotion: Bool,
        neighbors: @escaping () -> SwipeNeighborTabs
    ) {
        guard !declinedDrag else { return }
        if phase != .tracking {
            guard abs(translation.width) >= abs(translation.height) * Self.horizontalDominance else {
                declinedDrag = true
                return
            }
            landNow()
            askNeighbors = neighbors
            self.neighbors = neighbors()
            landedTabID = nil
            phase = .tracking
        }
        // Reduce Motion keeps the page still under the finger; the release
        // still decides, and the tab it lands on fades in.
        guard !reduceMotion else { return }
        travel = resisted(pages(translation.width, layoutDirection))
    }

    /// Finishes a drag on the bar whose release was heading for
    /// `predictedTranslation`: on to the neighbour that way when it reaches
    /// far enough and there is one, back where it started otherwise, with a
    /// shake when there is none.
    func release(
        _ predictedTranslation: CGSize, layoutDirection: LayoutDirection, reduceMotion: Bool,
        land: @escaping (UUID) -> Void
    ) {
        defer { declinedDrag = false }
        guard phase == .tracking else { return }
        let intent = pages(predictedTranslation.width, layoutDirection)
        guard abs(intent) >= Self.landingTravel else {
            settle(to: 0, landingOn: nil, land: nil, reduceMotion: reduceMotion)
            return
        }
        guard let target = intent > 0 ? neighbors.nextTabID : neighbors.previousTabID else {
            boundaryHits &+= 1
            settle(to: 0, landingOn: nil, land: nil, reduceMotion: reduceMotion)
            return
        }
        settle(to: intent > 0 ? 1 : -1, landingOn: target, land: land, reduceMotion: reduceMotion)
    }

    /// Moves one tab `direction` the way a swipe does, for what is no drag:
    /// VoiceOver's actions and a split's bubbles. Past an end it shakes the
    /// bar instead.
    func step(
        _ direction: AdjacentDirection, reduceMotion: Bool, neighbors: @escaping () -> SwipeNeighborTabs,
        land: @escaping (UUID) -> Void
    ) {
        landNow()
        guard phase == .idle else { return }
        let reached = neighbors()
        guard let target = direction.step > 0 ? reached.nextTabID : reached.previousTabID else {
            boundaryHits &+= 1
            return
        }
        askNeighbors = neighbors
        self.neighbors = reached
        landedTabID = nil
        settle(to: CGFloat(direction.step), landingOn: target, land: land, reduceMotion: reduceMotion)
    }

    /// The window shows another tab, whose neighbours are `neighbors`. A swipe
    /// still moving lets go without landing anywhere: the window moved on from
    /// somewhere else.
    func rest(beside neighbors: SwipeNeighborTabs) {
        if phase != .idle {
            generation &+= 1
            landingTabID = nil
            comeToRest()
        }
        self.neighbors = neighbors
    }

    // MARK: - Actions - Presentation

    /// Where the page `place` tabs on from the shown one sits, in points
    /// toward the trailing edge, as SwiftUI offsets a view in either writing
    /// direction: the shown tab at 0, its next at 1 and its previous at -1, as
    /// far along as the swipe has moved them.
    func offset(of place: CGFloat) -> CGFloat {
        (place - travel) * pageWidth
    }

    // MARK: - Mutators

    /// `width` points of finger travel, which a drag reports left to right
    /// in either writing direction, as pages toward the next tab.
    private func pages(_ width: CGFloat, _ layoutDirection: LayoutDirection) -> CGFloat {
        guard pageWidth > 0 else { return 0 }
        return -layoutDirection.semanticHorizontalTranslation(width) / pageWidth
    }

    /// `travel` as far as the page may follow it: a page either way while
    /// there is a tab that way, and past an end, a lean that grows ever more
    /// slowly toward `boundaryReach`.
    private func resisted(_ travel: CGFloat) -> CGFloat {
        let neighbor = travel > 0 ? neighbors.nextTabID : neighbors.previousTabID
        guard neighbor == nil else { return min(1, max(-1, travel)) }
        let lean = Self.boundaryReach * (1 - 1 / (abs(travel) * 3 + 1))
        return travel < 0 ? -lean : lean
    }

    /// Carries the page to `end` on the Space pager's release curve, then
    /// lands on `target` through `land`, or nowhere when there is none.
    /// Reduce Motion lands at once.
    private func settle(
        to end: CGFloat, landingOn target: UUID?, land: ((UUID) -> Void)?, reduceMotion: Bool
    ) {
        generation &+= 1
        let generation = generation
        phase = .settling
        landingTabID = target
        self.land = land
        guard !reduceMotion, pageWidth > 0 else {
            finish(generation, fades: target != nil)
            return
        }
        let settlement = SpacePagerSettlement(startPosition: travel, endPosition: end, generation: generation)
        withAnimation(settlement.animation, completionCriteria: .logicallyComplete) {
            travel = end
        } completion: { [weak self] in
            self?.finish(generation, fades: false)
        }
    }

    /// Lands the settle `generation` names, if it is still the one in flight:
    /// the tab it went to becomes the shown tab, with its own neighbours, in
    /// the same update that puts the page area back at rest, so the page that
    /// slid in stays where it is and the one it replaced waits beside it. A
    /// page that `fades` in, as Reduce Motion swaps it, starts clear.
    private func finish(_ generation: UInt, fades: Bool) {
        guard generation == self.generation, phase == .settling else { return }
        let target = landingTabID
        landingTabID = nil
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let target, let land {
                land(target)
                landedTabID = target
                if let askNeighbors { neighbors = askNeighbors() }
                if fades { shownOpacity = 0 }
            }
            comeToRest()
        }
        guard fades else { return }
        withAnimation(CrestMotion.reducedMotionFade) { shownOpacity = 1 }
    }

    /// Lands a settle still in flight at once, so the swipe that interrupts it
    /// begins from the tab it was going to.
    private func landNow() {
        guard phase == .settling else { return }
        finish(generation, fades: false)
    }

    private func comeToRest() {
        travel = 0
        phase = .idle
    }
}
