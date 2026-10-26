import AppKit
import QuartzCore
import SwiftUI

/// Retains native page roots and moves their actual views without publishing
/// gesture progress into the SwiftUI trees those roots contain.
@MainActor
final class SpacePagerViewport<Content: View>: NSView {
    struct Motion {
        let generation: UInt
        let origin: BrowserSpaceRuntimeAssignment
        var target: BrowserSpaceRuntimeAssignment?
        var offset: CGFloat = 0
        var initialOffset: CGFloat = 0
        var translation: CGFloat = 0
        var direction: CGFloat = 0
        var settledDestination: UUID?
        var transition: SpacePagerSettlement?
        var hasPreparedNeighbors = false
        var commitsSelection: Bool
    }

    private(set) var spaces: [SpaceModel] = []
    /// What the Spaces were at the last update, kept as values: the models
    /// change in place, so only a snapshot tells an update what moved.
    private var shownAssignments: [BrowserSpaceRuntimeAssignment] = []
    private var shownAccessPolicies: [SpaceAccessPolicy] = []
    private(set) var selectedSpaceID: UUID?
    private(set) var presentationSpaceID: UUID?
    private(set) var isInteractionLocked = false
    /// The last Next or Previous Space step the window took.
    private var spaceStep: BrowserSpaceStep?
    /// That step while it is new in the current update, which a slide follows
    /// around the ends of the Spaces only once.
    private var newSpaceStep: BrowserSpaceStep?
    private(set) var reduceMotion = false
    private(set) var layoutDirection = LayoutDirection.leftToRight
    private(set) var motion: Motion?
    private var generation: UInt = 0
    private var expectedSelection: UUID?
    private var hosts: [BrowserSpaceRuntimeAssignment: SpacePageHost<Content>] = [:]
    private var makeRoot: ((SpaceModel, Bool) -> SpacePageRoot<Content>)?
    private var selectSpace: (UUID) -> UUID = { $0 }
    private var lastSize = CGSize.zero
    private var presentation: SpacePagerPresentation?
    private var contentTopInsets: [UUID: CGFloat] = [:]
    private var pendingContentTopInsets: [UUID: CGFloat] = [:]
    private var motionDisplayLink: CADisplayLink?
    /// Which installation of the settling animations finishes the motion. A
    /// slide re-aimed at a new size replaces its animations, and the ones it
    /// replaced must not end it.
    private var settlementEpoch: UInt = 0
    private var maximumTrackingSpeed: CGFloat { bounds.width * SpacePagerSettlement.trackingPagesPerSecond }
    private lazy var frameObserver = SpacePagerFrameObserver { [weak self] interval in
        self?.advanceFrame(interval: interval)
    }
    private lazy var gesture: SpacePagerGesture<Content> = {
        @MainActor in SpacePagerGesture(viewport: self)
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { return nil }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    var gestureBounds: CGRect {
        let inset = max(0, presentation?.gestureTopInset ?? 0)
        return CGRect(x: bounds.minX, y: bounds.minY - inset, width: bounds.width, height: bounds.height + inset)
    }

    func update(
        spaces: [SpaceModel], selectedSpaceID: UUID,
        isInteractionLocked: Bool, spaceStep: BrowserSpaceStep? = nil, reduceMotion: Bool,
        layoutDirection: LayoutDirection,
        presentation: SpacePagerPresentation? = nil,
        contentTopInsets: [UUID: CGFloat] = [:],
        selectSpace: @escaping (UUID) -> UUID,
        makeRoot: @escaping (SpaceModel, Bool) -> SpacePageRoot<Content>
    ) {
        let assignments = spaces.map(BrowserSpaceRuntimeAssignment.init(space:))
        let accessPolicies = spaces.map(\.settings.accessPolicy)
        let assignmentsChanged = shownAssignments != assignments
        let selectionChanged = self.selectedSpaceID != selectedSpaceID
        let accessPoliciesChanged = shownAccessPolicies != accessPolicies
        shownAssignments = assignments
        shownAccessPolicies = accessPolicies
        let invalidatesMotion =
            assignmentsChanged || accessPoliciesChanged || isInteractionLocked
            || self.reduceMotion != reduceMotion || self.layoutDirection != layoutDirection
        self.presentation = presentation
        pendingContentTopInsets = contentTopInsets
        self.spaces = spaces
        self.selectedSpaceID = selectedSpaceID
        self.isInteractionLocked = isInteractionLocked
        newSpaceStep = spaceStep?.id == self.spaceStep?.id ? nil : spaceStep
        self.spaceStep = spaceStep
        self.reduceMotion = reduceMotion
        self.layoutDirection = layoutDirection
        self.selectSpace = selectSpace
        self.makeRoot = makeRoot

        if invalidatesMotion {
            cancelMotion()
            gesture.cancelCurrentGesture()
            presentationSpaceID = selectedSpaceID
            expectedSelection = nil
        } else if expectedSelection == selectedSpaceID {
            // A rapid accepted return can equal the old local ID. Its receipt
            // must be acknowledged even without a selectionChanged edge.
            expectedSelection = nil
            if motion == nil { presentationSpaceID = selectedSpaceID }
        } else if selectionChanged {
            // Actual authoritative selection changes supersede native motion;
            // unrelated updates carrying the old ID do not.
            expectedSelection = nil
            if let heading = motion?.settledDestination, !reduceMotion,
                let step = step(from: heading, to: selectedSpaceID)
            {
                // The slide no longer decides the selection, even if it ends
                // before the continuation starts. Its page is readied now,
                // with this update, so the continuation's own commit is light.
                motion?.commitsSelection = false
                prepareHosts(around: heading, retaining: selectedSpaceID, refreshContent: false)
                continueSettlingOnScreen(to: selectedSpaceID, from: heading, step: step)
            } else {
                cancelMotion()
                gesture.cancelCurrentGesture()
                if let origin = presentationSpaceID, !reduceMotion, let step = step(from: origin, to: selectedSpaceID) {
                    // Retained pages keep their visible content until the slide
                    // finishes. The latest roots are supplied at completion.
                    prepareHosts(around: selectedSpaceID, retaining: origin, refreshContent: false)
                    animate(to: selectedSpaceID, step: step, commitsSelection: false)
                    return
                }
                // A direct nonadjacent choice presents its authoritative page.
                // It does not create a compressed strip of unrelated neighbors.
                presentationSpaceID = selectedSpaceID
            }
        }
        guard motion == nil else {
            updateAccessibility()
            publishPresentation(sampleAnimated: true)
            return
        }
        if presentationSpaceID == nil { presentationSpaceID = selectedSpaceID }
        applyContentTopInsets(animated: !invalidatesMotion && !selectionChanged)
        prepareHosts(around: presentationSpaceID ?? selectedSpaceID)
        positionHosts()
        updateAccessibility()
        publishPresentation()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        gesture.attach(to: window)
        if window == nil {
            presentationSpaceID = expectedSelection ?? selectedSpaceID
            cancelMotion()
            publishPresentation()
        } else if motion == nil, let presentationSpaceID {
            // Detachment can cancel a slide before its deferred root refresh.
            prepareHosts(around: presentationSpaceID)
            positionHosts()
            updateAccessibility()
            publishPresentation()
        }
    }

    override func layout() {
        super.layout()
        // A sidebar animating beside a settling slide resizes this viewport.
        // The slide keeps going: the pages it moves and the moment it began
        // are read before the pages resize, and it is re-aimed after.
        var settling: (previousWidth: CGFloat, moving: [BrowserSpaceRuntimeAssignment], began: CFTimeInterval?)?
        if lastSize != bounds.size {
            let previousWidth = lastSize.width
            lastSize = bounds.size
            if motion?.transition != nil, previousWidth > 0, bounds.width > 0 {
                settling = (previousWidth, settlingHosts, settlementBeginTime)
            } else if motion != nil {
                cancelMotion()
                presentationSpaceID = selectedSpaceID
                if let presentationSpaceID {
                    prepareHosts(around: presentationSpaceID)
                    updateAccessibility()
                }
            }
        }
        for (key, host) in hosts where host.frame.size != pageSize(for: key) {
            host.setFrameSize(pageSize(for: key))
        }
        if let settling {
            resizeSettlement(from: settling.previousWidth, moving: settling.moving, beganAt: settling.began)
        }
        if motion == nil {
            positionHosts()
            publishPresentation()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local), !isHiddenOrHasHiddenAncestor else { return nil }
        // During settling AppKit's model frames already describe the endpoint.
        // Controls become available when their visible frames have arrived.
        guard motion == nil, expectedSelection == nil,
            let selectedSpaceID, let key = assignment(for: selectedSpaceID)
        else { return self }
        return hosts[key]?.hitTest(local) ?? self
    }

    func teardown() {
        gesture.attach(to: nil)
        presentationSpaceID = expectedSelection ?? selectedSpaceID
        cancelMotion()
        publishPresentation()
        for host in hosts.values { host.removeFromSuperview() }
        hosts.removeAll()
        makeRoot = nil
    }

    func neighbor(forPhysicalDirection direction: CGFloat) -> BrowserSpaceRuntimeAssignment? {
        guard let presentationSpaceID else { return nil }
        let forward = layoutDirection == .leftToRight ? direction < 0 : direction > 0
        guard
            let id = BrowserChromeAccessibility.adjacentSpaceID(
                spaces: spaces, selectedSpaceID: presentationSpaceID, direction: forward ? .next : .previous)
        else { return nil }
        return assignment(for: id)
    }

    func beginInteractiveMotion() -> UInt? {
        guard !isInteractionLocked, bounds.width > 0, spaces.count > 1 else { return nil }
        stopPresentationSampling()
        let previous = motion
        let originID = previous?.origin.spaceID ?? presentationSpaceID
        guard let originID, var origin = assignment(for: originID), hosts[origin] != nil else { return nil }
        var inheritedOffset = previous.map { visibleOffset(for: origin, during: $0) } ?? 0
        if previous != nil, let index = spaces.firstIndex(where: { $0.id == origin.spaceID }) {
            // Restart from the nearest visible page, using one presentation
            // sample for the entire strip. A newly admitted neighbor's layer
            // can still report geometry from an earlier layout transaction.
            let direction: CGFloat = layoutDirection == .leftToRight ? 1 : -1
            // A slide around the ends reaches a page one strip length away.
            let reached = index + Int((-inheritedOffset * direction / bounds.width).rounded())
            let count = spaces.count
            let nearestIndex = count > 2 ? (reached % count + count) % count : min(count - 1, max(0, reached))
            let nearest = BrowserSpaceRuntimeAssignment(space: spaces[nearestIndex])
            if hosts[nearest] != nil {
                let placed = SpacePagerInterpolation.index(nearestIndex, near: CGFloat(reached), count: count)
                inheritedOffset += CGFloat(placed - index) * bounds.width * direction
                origin = nearest
            }
        }
        generation &+= 1
        // Capture presentation before removing an interrupted animation. The new
        // gesture owns its displacement independently of this inherited offset.
        stopHostAnimations()
        presentationSpaceID = origin.spaceID
        motion = Motion(
            generation: generation, origin: origin, offset: inheritedOffset,
            initialOffset: inheritedOffset,
            commitsSelection: true)
        positionHosts()
        updateAccessibility()
        publishPresentation()
        return generation
    }

    func updateInteractiveMotion(deltaX: CGFloat, token: UInt) -> Bool {
        guard var current = motion, current.generation == token, current.settledDestination == nil,
            !isInteractionLocked, !isHiddenOrHasHiddenAncestor, window != nil
        else { return false }
        if current.direction == 0, deltaX != 0 {
            current.direction = deltaX < 0 ? -1 : 1
            current.target = neighbor(forPhysicalDirection: current.direction)
            if let target = current.target, hosts[target] == nil {
                // Normal input already has its destination. Only a gesture
                // outrunning the bounded cache needs this particular page.
                prepareHosts(around: current.origin.spaceID, retaining: target.spaceID, refreshContent: false)
            }
        }
        let minimum: CGFloat = neighbor(forPhysicalDirection: -1) == nil ? 0 : -bounds.width
        let maximum: CGFloat = neighbor(forPhysicalDirection: 1) == nil ? 0 : bounds.width
        let availableTravel =
            current.direction < 0 ? current.initialOffset - minimum : maximum - current.initialOffset
        let pending = current.initialOffset + current.translation - current.offset
        if deltaX * pending < 0 {
            // Reverse from what is visible, discarding unpresented travel. A
            // fast outward burst must not create a queue to unwind first.
            current.translation = current.offset - current.initialOffset
        }
        // Stop at the destination while tracking. Discard excess input so a
        // reversal moves immediately instead of first unwinding hidden travel.
        let travel = min(max(0, availableTravel), max(0, (current.translation + deltaX) * current.direction))
        current.translation = travel * current.direction
        motion = current
        startPresentationSampling()
        return true
    }

    func advanceFrame(interval: TimeInterval) {
        guard var current = motion else { return }
        if let destination = current.settledDestination {
            publishPresentation(sampleAnimated: true)
            // After the native slide has started, ready the page beyond its
            // destination. Rapid consecutive swipes can interrupt before the
            // selection receipt would normally admit that neighbor. Keep the
            // visible roots untouched and retain the same bounded cache.
            if !current.hasPreparedNeighbors, motion?.generation == current.generation {
                motion?.hasPreparedNeighbors = true
                prepareHosts(around: destination, retaining: current.origin.spaceID, refreshContent: false)
            }
            return
        }
        let pending = current.initialOffset + current.translation - current.offset
        guard pending != 0 else { return }
        // Slow input tracks point-for-point at display cadence. Fast input is
        // bounded to four page widths per second. After a missed frame, take
        // one frame's step rather than jumping through all the elapsed travel.
        let budget = maximumTrackingSpeed * min(1.0 / 60, max(0, interval))
        let delta = min(abs(pending), budget) * (pending < 0 ? -1 : 1)
        guard delta != 0 else { return }
        current.offset += delta
        motion = current
        positionHosts()
        publishPresentation()
    }

    func endInteractiveMotion(velocity: CGFloat, cancelled: Bool, token: UInt) -> Bool {
        guard let current = motion, current.generation == token, current.settledDestination == nil,
            !isInteractionLocked, !isHiddenOrHasHiddenAncestor, window != nil
        else { return false }
        let travel = max(0, current.translation * current.direction)
        // A fresh flick must qualify on its own even while the incoming page
        // still has distance to travel. Slow drags also retain visible progress.
        let releaseVelocity = cancelled || travel == 0 ? 0 : velocity
        let progress = max(travel, current.offset * current.direction)
        let projectedTravel = progress + releaseVelocity * current.direction * 0.15
        let completes = !cancelled && travel > 0 && projectedTravel >= bounds.width / 2
        let destination = completes ? current.target?.spaceID : nil
        settleMotion(to: destination ?? current.origin.spaceID)
        return true
    }

    func step(_ direction: BrowserSpaceSwipeDirection) {
        guard !isInteractionLocked else { return }
        guard let token = beginInteractiveMotion(), let current = motion,
            let next = BrowserChromeAccessibility.adjacentSpaceID(
                spaces: spaces, selectedSpaceID: current.origin.spaceID,
                direction: direction == .next ? .next : .previous)
        else {
            if let current = motion, current.settledDestination == nil {
                settleMotion(to: current.origin.spaceID)
            }
            return
        }
        guard motion?.generation == token else { return }
        let physical: CGFloat = (direction == .next ? -1 : 1) * (layoutDirection == .leftToRight ? 1 : -1)
        motion?.direction = physical
        motion?.target = assignment(for: next)
        if let target = motion?.target, hosts[target] == nil {
            prepareHosts(around: current.origin.spaceID, retaining: next, refreshContent: false)
        }
        settleMotion(to: next)
    }

    func cancelMotion() {
        stopPresentationSampling()
        generation &+= 1
        motion = nil
        stopHostAnimations()
        positionHosts()
        updateAccessibility()
    }

    private func animate(to destination: UUID, step: Int, commitsSelection: Bool) {
        guard let presentationSpaceID, let origin = assignment(for: presentationSpaceID),
            let target = assignment(for: destination)
        else { return }
        generation &+= 1
        let direction: CGFloat = (step > 0 ? -1 : 1) * (layoutDirection == .leftToRight ? 1 : -1)
        motion = Motion(
            generation: generation, origin: origin, target: target, direction: direction,
            commitsSelection: commitsSelection)
        positionHosts()
        updateAccessibility()
        settleMotion(to: destination)
    }

    /// How far the strip moves to show `target` from `origin`: one Space
    /// forward or back, between neighbours or for a Next or Previous step
    /// around the ends of the Spaces; nil for a choice further away.
    private func step(from origin: UUID, to target: UUID) -> Int? {
        guard let originIndex = spaces.firstIndex(where: { $0.id == origin }),
            let targetIndex = spaces.firstIndex(where: { $0.id == target })
        else { return nil }
        if abs(targetIndex - originIndex) == 1 { return targetIndex - originIndex }
        guard spaces.count > 2, let direction = newSpaceStep?.direction(from: origin, to: target) else { return nil }
        return direction == .next ? 1 : -1
    }

    /// Continues the settling slide toward `destination` once the update that
    /// selected it is on screen. That update can lay out a whole new Space
    /// before it reaches the screen, and the slide keeps moving meanwhile, so
    /// a continuation read from its position now would draw the page back by
    /// the distance covered by then. A slide that finished in the meantime
    /// slides on from the Space it reached.
    private func continueSettlingOnScreen(to destination: UUID, from heading: UUID, step: Int) {
        Task { @MainActor [weak self] in
            guard let self, self.selectedSpaceID == destination, self.expectedSelection == nil,
                !self.isInteractionLocked
            else { return }
            if !self.continueSettling(to: destination, from: heading, step: step) {
                guard self.motion == nil, self.presentationSpaceID == heading, !self.reduceMotion else { return }
                self.prepareHosts(around: destination, retaining: heading, refreshContent: false)
                self.animate(to: destination, step: step, commitsSelection: false)
            }
            // Main-actor work queued behind this can hold the run loop's
            // commit back while the earlier slide keeps moving on screen. The
            // continuation starts from where the page is now, so it goes to
            // the screen now.
            CATransaction.flush()
        }
    }

    /// A selection that arrives while a slide is still settling continues from
    /// what is on screen, starting at the Space that slide was heading to.
    /// Measured from the Space shown before the slide, the next one along
    /// would look two pages away and appear without motion.
    private func continueSettling(to destination: UUID, from heading: UUID, step: Int) -> Bool {
        guard !reduceMotion, let current = motion, current.settledDestination == heading,
            let origin = assignment(for: heading), hosts[origin] != nil,
            let target = assignment(for: destination)
        else { return false }
        let offset = settlingOffset(for: origin, during: current) ?? visibleOffset(for: origin, during: current)
        gesture.cancelCurrentGesture()
        stopPresentationSampling()
        stopHostAnimations()
        generation &+= 1
        presentationSpaceID = heading
        motion = Motion(
            generation: generation, origin: origin, target: target, offset: offset, initialOffset: offset,
            direction: (step > 0 ? -1 : 1) * (layoutDirection == .leftToRight ? 1 : -1),
            commitsSelection: false)
        // The page the slide left is still partly on screen, so the cache
        // keeps the strip around the heading Space rather than the new one.
        prepareHosts(around: heading, retaining: destination, refreshContent: false)
        positionHosts()
        updateAccessibility()
        settleMotion(to: destination)
        return true
    }

    /// Where `key`'s page is now on the settling slide's own curve, timed
    /// from when Core Animation began it; nil once the page's slide has
    /// ended. A layer's presentation runs about a frame behind, which is a
    /// visible step at the start of a slide.
    private func settlingOffset(for key: BrowserSpaceRuntimeAssignment, during current: Motion) -> CGFloat? {
        guard let transition = current.transition, bounds.width > 0,
            let slide = hosts[key]?.layer.flatMap(Self.slideAnimation),
            let index = spaces.firstIndex(where: { $0.id == key.spaceID })
        else { return nil }
        // Zero is a slide Core Animation has not committed yet.
        let elapsed = slide.beginTime > 0 ? CACurrentMediaTime() - slide.beginTime : 0
        let position = transition.position(after: elapsed)
        let placed = SpacePagerInterpolation.index(index, near: transition.startPosition, count: spaces.count)
        let direction: CGFloat = layoutDirection == .leftToRight ? 1 : -1
        return (CGFloat(placed) - position) * bounds.width * direction
    }

    private func visibleOffset(for key: BrowserSpaceRuntimeAssignment, during current: Motion) -> CGFloat {
        guard let host = hosts[key] else { return 0 }
        if current.settledDestination != nil {
            return host.layer?.presentation()?.frame.minX ?? restingOffset(for: key, during: current)
                + current.offset
        }
        return host.frame.minX
    }

    private func settleMotion(to destination: UUID) {
        guard var current = motion, assignment(for: destination) != nil else { return }
        let token = current.generation
        let startOffset = visibleOffset(for: current.origin, during: current)
        current.offset = startOffset
        current.settledDestination = destination
        let targetOffset: CGFloat = destination == current.origin.spaceID ? 0 : current.direction * bounds.width
        motion = current
        updateAccessibility()
        guard !reduceMotion, abs(targetOffset - startOffset) > 0.01 else {
            finishMotion(token: token, destination: destination)
            return
        }
        let originIndex = spaces.firstIndex { $0.id == current.origin.spaceID } ?? 0
        let direction: CGFloat = layoutDirection == .leftToRight ? 1 : -1
        let transition = SpacePagerSettlement(
            startPosition: CGFloat(originIndex) - startOffset / bounds.width * direction,
            endPosition: CGFloat(originIndex) - targetOffset / bounds.width * direction,
            generation: token)
        current.transition = transition
        motion = current
        let moving = hosts.filter { key, host in
            let end = restingOffset(for: key, during: current) + targetOffset
            let endFrame = CGRect(
                x: end, y: topInset(at: transition.endPosition),
                width: bounds.width, height: pageSize(for: key).height)
            return needsMotion(for: key, host: host, destination: endFrame)
        }
        installSettlement(transition, moving: Array(moving.keys), destination: destination)
        startPresentationSampling()
    }

    /// Moves the `moving` pages along `transition`, each with its own native
    /// animation on one clock and curve, and finishes the motion when they end.
    private func installSettlement(
        _ transition: SpacePagerSettlement, moving: [BrowserSpaceRuntimeAssignment], destination: UUID
    ) {
        let finish = settlementFinish(transition, destination: destination)
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = transition.duration
                context.timingFunction = transition.timingFunction
                // All native leaves install their animations in this transaction,
                // with the same clock and curve. Sampling must not drive settling.
                publishPresentation()
                for key in moving {
                    guard let host = hosts[key] else { continue }
                    host.animations = ["frameOrigin": settlementAnimation(for: key, along: transition)]
                    host.animator().setFrameOrigin(
                        settlementOrigin(for: key, at: transition.endPosition, along: transition))
                }
            }, completionHandler: finish)
    }

    /// Re-aims the settling slide at the viewport's new width. Its `moving`
    /// pages keep the moment the slide began and the Space positions it moves
    /// between, so it neither restarts nor ends early. AppKit installs no
    /// animator animation while it lays a view out, so the pages' layers take
    /// the slide directly.
    private func resizeSettlement(
        from previousWidth: CGFloat, moving: [BrowserSpaceRuntimeAssignment], beganAt began: CFTimeInterval?
    ) {
        guard var current = motion, let transition = current.transition,
            let destination = current.settledDestination
        else { return }
        let scale = bounds.width / previousWidth
        current.offset *= scale
        current.initialOffset *= scale
        current.translation *= scale
        motion = current
        stopHostAnimations()
        CATransaction.begin()
        CATransaction.setCompletionBlock(settlementFinish(transition, destination: destination))
        for key in moving {
            guard let host = hosts[key] else { continue }
            let animation = settlementAnimation(for: key, along: transition)
            animation.keyPath = "position"
            // Zero, for a slide Core Animation has not committed yet, starts now.
            animation.beginTime = began ?? 0
            host.setFrameOrigin(settlementOrigin(for: key, at: transition.endPosition, along: transition))
            host.layer?.add(animation, forKey: "position")
        }
        CATransaction.commit()
    }

    /// Finishes the motion once the settling animations installed now end. A
    /// slide re-aimed later replaces them, and their end no longer counts.
    private func settlementFinish(_ transition: SpacePagerSettlement, destination: UUID) -> () -> Void {
        settlementEpoch &+= 1
        let epoch = settlementEpoch
        let token = transition.generation
        return { [weak self] in
            Task { @MainActor in
                guard let self, self.settlementEpoch == epoch else { return }
                self.finishMotion(token: token, destination: destination)
            }
        }
    }

    /// The keyframes that move `key`'s page along `transition`.
    private func settlementAnimation(
        for key: BrowserSpaceRuntimeAssignment, along transition: SpacePagerSettlement
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation()
        transition.configure(animation)
        // Both axes share the same fractional Space coordinate. Crossed
        // boundaries preserve toolbar height during an interrupted reversal.
        animation.values = transition.positions.map {
            NSValue(point: settlementOrigin(for: key, at: $0, along: transition))
        }
        animation.keyTimes = transition.positions.map {
            NSNumber(
                value: Double(($0 - transition.startPosition) / (transition.endPosition - transition.startPosition)))
        }
        return animation
    }

    /// Where `key`'s page sits while the strip shows the fractional Space
    /// `position` of `transition`. A page keeps the place it had where the
    /// transition began, so none switches ends partway.
    private func settlementOrigin(
        for key: BrowserSpaceRuntimeAssignment, at position: CGFloat, along transition: SpacePagerSettlement
    ) -> NSPoint {
        let index = spaces.firstIndex { $0.id == key.spaceID } ?? 0
        let placed = SpacePagerInterpolation.index(index, near: transition.startPosition, count: spaces.count)
        let pageIndex = CGFloat(placed)
        let direction: CGFloat = layoutDirection == .leftToRight ? 1 : -1
        return NSPoint(x: (pageIndex - position) * bounds.width * direction, y: topInset(at: position))
    }

    /// The pages the settling slide moves.
    private var settlingHosts: [BrowserSpaceRuntimeAssignment] {
        hosts.filter { $0.value.layer.flatMap(Self.slideAnimation) != nil }.map(\.key)
    }

    /// When Core Animation began the settling slide, once it has committed it.
    private var settlementBeginTime: CFTimeInterval? {
        hosts.values.lazy.compactMap { $0.layer.flatMap(Self.slideAnimation)?.beginTime }.first { $0 > 0 }
    }

    /// The slide's own animation on a page's layer, beside an inset change.
    private static func slideAnimation(on layer: CALayer) -> CAAnimation? {
        layer.animationKeys()?.first { $0 != "sidebarInsetChange" }.flatMap(layer.animation(forKey:))
    }

    private func finishMotion(token: UInt, destination: UUID?) {
        guard let current = motion, current.generation == token,
            assignment(for: current.origin.spaceID) == current.origin,
            let destination, assignment(for: destination) != nil
        else { return }
        stopPresentationSampling()
        let committedSelection = expectedSelection ?? selectedSpaceID
        motion = nil
        presentationSpaceID = destination
        if current.commitsSelection, destination != committedSelection { expectedSelection = destination }
        stopHostAnimations()
        applyContentTopInsets(animated: true)
        positionHosts()
        updateAccessibility()
        publishPresentation()
        if current.commitsSelection, destination != committedSelection {
            let actual = selectSpace(destination)
            if actual != destination {
                expectedSelection = nil
                selectedSpaceID = actual
                presentationSpaceID = actual
                prepareHosts(around: actual)
                positionHosts()
                updateAccessibility()
                publishPresentation()
                return
            }
        }
        // Model updates refresh content after visual completion, never once
        // per progress sample. Cancellation may finish without a model update.
        if expectedSelection == nil {
            prepareHosts(around: destination)
            positionHosts()
            updateAccessibility()
        }
    }

    private func publishPresentation(sampleAnimated: Bool = false) {
        guard let presentation, let originID = motion?.origin.spaceID ?? presentationSpaceID,
            let index = spaces.firstIndex(where: { $0.id == originID })
        else { return }
        let offset: CGFloat
        if let motion {
            offset =
                sampleAnimated && motion.settledDestination != nil
                ? visibleOffset(for: motion.origin, during: motion) : motion.offset
        } else {
            offset = 0
        }
        let direction: CGFloat = layoutDirection == .leftToRight ? 1 : -1
        let position = CGFloat(index) - (bounds.width > 0 ? offset / bounds.width * direction : 0)
        presentation.publish(
            .init(
                generation: generation, spaceIDs: spaces.map(\.id), position: position,
                phase: motion == nil ? .idle : motion?.settledDestination == nil ? .tracking : .settling,
                destinationID: motion?.settledDestination ?? motion?.target?.spaceID ?? originID,
                transition: motion?.transition))
    }

    private func startPresentationSampling() {
        guard motionDisplayLink == nil, window != nil else { return }
        let link = displayLink(target: frameObserver, selector: #selector(SpacePagerFrameObserver.sample(_:)))
        link.add(to: .main, forMode: .common)
        motionDisplayLink = link
    }

    private func stopPresentationSampling() {
        motionDisplayLink?.invalidate()
        motionDisplayLink = nil
    }

    private func assignment(for id: UUID) -> BrowserSpaceRuntimeAssignment? {
        spaces.first { $0.id == id }.map(BrowserSpaceRuntimeAssignment.init(space:))
    }

    private func prepareHosts(around id: UUID, retaining extra: UUID? = nil, refreshContent: Bool = true) {
        guard let makeRoot, let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        let neighbors = spaces[max(0, index - 1)...min(spaces.count - 1, index + 1)]
        var required = Set(neighbors.map { BrowserSpaceRuntimeAssignment(space: $0) })
        if let extra, let key = assignment(for: extra) { required.insert(key) }
        let spare = spaces.enumerated().filter {
            let key = BrowserSpaceRuntimeAssignment(space: $0.element)
            return hosts[key] != nil && !required.contains(key)
        }.sorted { abs($0.offset - index) < abs($1.offset - index) }
            .prefix(max(0, 4 - required.count))
        required.formUnion(spare.map { BrowserSpaceRuntimeAssignment(space: $0.element) })
        for key in hosts.keys where !required.contains(key) {
            hosts.removeValue(forKey: key)?.removeFromSuperview()
        }
        for space in spaces {
            let key = BrowserSpaceRuntimeAssignment(space: space)
            guard required.contains(key) else { continue }
            if let host = hosts[key] {
                if refreshContent { host.hostingView.rootView = makeRoot(space, space.id == selectedSpaceID) }
            } else {
                let host = SpacePageHost(root: makeRoot(space, space.id == selectedSpaceID))
                host.frame = CGRect(
                    x: restingOffset(for: key, during: motion) + (motion?.offset ?? 0),
                    y: topInset(at: displayedPosition),
                    width: bounds.width, height: pageSize(for: key).height)
                host.hostingView.frame = host.bounds
                hosts[key] = host
                addSubview(host)
            }
        }
    }

    private func restingOffset(for key: BrowserSpaceRuntimeAssignment, during current: Motion?) -> CGFloat {
        guard let originID = current?.origin.spaceID ?? presentationSpaceID,
            let origin = spaces.firstIndex(where: { $0.id == originID }),
            let index = spaces.firstIndex(where: { $0.id == key.spaceID })
        else { return 0 }
        let distance = CGFloat(
            SpacePagerInterpolation.index(index, near: CGFloat(origin), count: spaces.count) - origin)
        return distance * (layoutDirection == .leftToRight ? 1 : -1) * bounds.width
    }

    private func positionHosts() {
        for (key, host) in hosts {
            let offset = restingOffset(for: key, during: motion) + (motion?.offset ?? 0)
            let origin = NSPoint(x: offset, y: topInset(at: displayedPosition))
            let frame = CGRect(origin: origin, size: pageSize(for: key))
            guard motion == nil || needsMotion(for: key, host: host, destination: frame) else { continue }
            if host.frame.origin != origin { host.setFrameOrigin(origin) }
            if motion == nil, host.frame.size != frame.size { host.setFrameSize(frame.size) }
        }
    }

    private var displayedPosition: CGFloat {
        let origin = motion?.origin.spaceID ?? presentationSpaceID
        let index = spaces.firstIndex { $0.id == origin } ?? 0
        let direction: CGFloat = layoutDirection == .leftToRight ? 1 : -1
        return CGFloat(index) - (bounds.width > 0 ? (motion?.offset ?? 0) / bounds.width * direction : 0)
    }

    /// Startup and pin changes can arrive during a swipe. Keep that swipe's
    /// geometry stable, then animate the new inset once selection has settled.
    /// An additive correction survives a new horizontal gesture without retiming it.
    private func applyContentTopInsets(animated: Bool) {
        guard contentTopInsets != pendingContentTopInsets else { return }
        let visible = presentationSpaceID.flatMap { assignment(for: $0) }.flatMap { hosts[$0] }
        let previousY = visible?.layer?.presentation()?.frame.minY ?? topInset(at: displayedPosition)
        contentTopInsets = pendingContentTopInsets
        positionHosts()
        let delta = previousY - topInset(at: displayedPosition)
        for host in hosts.values {
            host.layer?.removeAnimation(forKey: "sidebarInsetChange")
            guard animated, !reduceMotion, window != nil, abs(delta) > 0.01 else { continue }
            let animation = CABasicAnimation(keyPath: "position.y")
            SpacePagerSettlement(startPosition: 0, endPosition: 1, generation: generation).configure(animation)
            animation.isAdditive = true
            animation.fromValue = delta
            animation.toValue = 0
            host.layer?.add(animation, forKey: "sidebarInsetChange")
        }
    }

    private func topInset(at position: CGFloat) -> CGFloat {
        guard let blend = SpacePagerInterpolation(position: position, count: spaces.count) else { return 0 }
        let lower = contentTopInsets[spaces[blend.lower].id] ?? 0
        let upper = contentTopInsets[spaces[blend.upper].id] ?? 0
        return min(bounds.height, max(0, lower + (upper - lower) * blend.fraction))
    }

    private func pageSize(for key: BrowserSpaceRuntimeAssignment) -> CGSize {
        CGSize(width: bounds.width, height: max(0, bounds.height - max(0, contentTopInsets[key.spaceID] ?? 0)))
    }

    private func needsMotion(
        for key: BrowserSpaceRuntimeAssignment, host: NSView, destination: CGRect
    ) -> Bool {
        // Retaining a layout does not require moving it on every input sample.
        // Native frame changes invalidate the hosting tree's global geometry,
        // even when the whole page remains outside the viewport.
        key == motion?.origin || key == motion?.target
            || host.frame.intersects(bounds) || destination.intersects(bounds)
    }

    private func stopHostAnimations() {
        // Only the pager animates these wrapper layers. Removing their motion
        // leaves descendant SwiftUI animations alone. Position is always set
        // through NSView immediately afterward, including interruption rebasing.
        for host in hosts.values {
            for key in host.layer?.animationKeys() ?? [] where key != "sidebarInsetChange" {
                host.layer?.removeAnimation(forKey: key)
            }
        }
    }

    private func updateAccessibility() {
        let hasPresentation = presentationSpaceID.flatMap { assignment(for: $0) } != nil
        for (key, host) in hosts {
            // The cache is bounded in prepareHosts. Keep those layouts alive
            // throughout a slide; hiding and restoring distant cached hosts
            // adds layout work exactly when the page surface changes. Their
            // stationary frames remain outside the clipped viewport.
            host.isHidden = !hasPresentation
            host.setAccessibilityHidden(key.spaceID != selectedSpaceID || motion != nil || expectedSelection != nil)
        }
    }
}

/// Keeps the Objective-C display-link target independent of the generic page root.
@MainActor
private final class SpacePagerFrameObserver: NSObject {
    let update: @MainActor (TimeInterval) -> Void

    init(update: @escaping @MainActor (TimeInterval) -> Void) { self.update = update }

    @objc func sample(_ link: CADisplayLink) { update(link.targetTimestamp - link.timestamp) }
}
