import AppKit
import QuartzCore
import SwiftUI

/// A passive strip of real content surfaces. Only the sidebar owns gestures;
/// web history gestures continue to belong to WebKit.
@MainActor
final class SpaceContentPagerView<Content: View & Equatable>: NSView {
    private var spaces: [SpaceModel] = []
    private var selectedSpaceID: UUID?
    private var lockedSpaceIDs: Set<UUID> = []
    private var layoutDirection = LayoutDirection.leftToRight
    private var presentation: SpacePagerPresentation?
    private var snapshot: SpacePagerPresentation.Snapshot?
    private var transition: SpacePagerSettlement?
    private var hosts: [BrowserSpaceRuntimeAssignment: SpacePageHost<Content>] = [:]
    private var makeRoot: ((SpaceModel, Bool) -> SpacePageRoot<Content>)?
    private var lastSize = CGSize.zero
    private var preparedDestination: UUID?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    func update(
        spaces: [SpaceModel], selectedSpaceID: UUID, lockedSpaceIDs: Set<UUID>,
        layoutDirection: LayoutDirection, presentation: SpacePagerPresentation?,
        makeRoot: @escaping (SpaceModel, Bool) -> SpacePageRoot<Content>
    ) {
        let changedLocks = self.lockedSpaceIDs.symmetricDifference(lockedSpaceIDs)
        let assignments = Set(spaces.map(BrowserSpaceRuntimeAssignment.init(space:)))
        // Withdraw old clear surfaces before admitting roots for a new lock or
        // profile assignment. In-flight reversal cannot resurrect those hosts.
        for key in hosts.keys where changedLocks.contains(key.spaceID) || !assignments.contains(key) {
            hosts.removeValue(forKey: key)?.removeFromSuperview()
        }
        self.spaces = spaces
        self.selectedSpaceID = selectedSpaceID
        self.lockedSpaceIDs = lockedSpaceIDs
        self.layoutDirection = layoutDirection
        self.makeRoot = makeRoot
        if self.presentation !== presentation {
            disconnect()
            self.presentation = presentation
            presentation?.observe(owner: self) { [weak self] in self?.receive($0) }
        }
        let current = matchingSnapshot ?? restingSnapshot(selectedSpaceID)
        snapshot = current
        prepareHosts(
            at: current.position, destination: current.destinationID, refresh: current.phase == .idle,
            preparesNeighbors: current.phase == .idle)
        if transition == nil { positionHosts(at: current.position) }
        updateAccessibility()
    }

    func disconnect() {
        presentation?.removeObserver(owner: self)
        presentation = nil
        transition = nil
        for host in hosts.values { host.layer?.removeAllAnimations() }
    }

    override func layout() {
        super.layout()
        guard lastSize != bounds.size else { return }
        lastSize = bounds.size
        // A sidebar animation resizes this viewport on every frame. A slide
        // already running keeps going: its pages are re-aimed at the new size
        // from the moment it began, rather than restarting it every frame.
        let moving = transition == nil ? [] : slidingHosts
        let began = transition == nil ? nil : slideBeginTime
        for host in hosts.values {
            host.layer?.removeAllAnimations()
            // Keep offscreen pages cached without reflowing their native content.
            if host.hostingView.rootView.contentPresentation != .inactive, host.frame.size != bounds.size {
                host.setFrameSize(bounds.size)
            }
        }
        if let snapshot {
            prepareHosts(
                at: snapshot.position, destination: snapshot.destinationID, refresh: false,
                preparesNeighbors: snapshot.phase == .idle)
            positionHosts(at: snapshot.position)
        }
        if let transition { resumeSlide(moving, along: transition, beganAt: began) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(convert(point, from: superview)),
            snapshot?.phase == .idle, snapshot?.destinationID == selectedSpaceID
        else { return nil }
        return super.hitTest(point)
    }

    private var matchingSnapshot: SpacePagerPresentation.Snapshot? {
        guard let value = presentation?.snapshot, value.spaceIDs == spaces.map(\.id) else { return nil }
        return value
    }

    private func restingSnapshot(_ id: UUID) -> SpacePagerPresentation.Snapshot {
        .init(
            generation: 0, spaceIDs: spaces.map(\.id),
            position: CGFloat(spaces.firstIndex { $0.id == id } ?? 0), phase: .idle, destinationID: id)
    }

    private func receive(_ value: SpacePagerPresentation.Snapshot) {
        guard value.spaceIDs == spaces.map(\.id) else { return }
        // A selection that arrives mid-slide leaves the roots built for the
        // Space selected before it, so the page it lands on would never take
        // input. A settled slide supplies the latest roots, as the sidebar's
        // pager does.
        let settles = value.phase == .idle && snapshot?.phase != .idle
        snapshot = value
        if let release = value.transition, value.phase == .settling, bounds.width > 0 {
            if transition == release {
                // Admit the next neighbor once the common native animation has
                // started. Existing visible roots are never refreshed here.
                if preparedDestination != value.destinationID {
                    preparedDestination = value.destinationID
                    prepareHosts(at: value.position, destination: value.destinationID, refresh: false)
                    updateAccessibility()
                }
                return
            }
            prepareHosts(
                at: release.startPosition, destination: value.destinationID, refresh: false,
                preparesNeighbors: false)
            stopAnimations()
            positionHosts(at: release.startPosition)
            transition = release
            let moving = hosts.filter { key, host in
                needsMotion(host, to: origin(for: key, at: release.endPosition, placedNear: release.startPosition))
            }
            slide(Array(moving.keys), along: release)
        } else {
            stopAnimations()
            prepareHosts(
                at: value.position, destination: value.destinationID, refresh: settles,
                preparesNeighbors: value.phase == .idle)
            positionHosts(at: value.position)
        }
        updateAccessibility()
    }

    /// Moves the pages `keys` name along `release`, with the pager's native
    /// curve.
    private func slide(_ keys: [BrowserSpaceRuntimeAssignment], along release: SpacePagerSettlement) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = release.duration
            context.timingFunction = release.timingFunction
            for key in keys {
                guard let host = hosts[key] else { continue }
                let animation = CABasicAnimation()
                release.configure(animation)
                animation.fromValue = NSValue(point: origin(for: key, at: release.startPosition))
                host.animations = ["frameOrigin": animation]
                host.animator().setFrameOrigin(
                    origin(for: key, at: release.endPosition, placedNear: release.startPosition))
            }
        }
    }

    /// Continues the slide along `release` for the pages `keys` name after a
    /// resize, from the moment it began, so it goes on from where it is
    /// instead of starting over. AppKit installs no animator animation while
    /// it lays a view out, so the pages' layers take the slide directly.
    private func resumeSlide(
        _ keys: [BrowserSpaceRuntimeAssignment], along release: SpacePagerSettlement, beganAt beginTime: CFTimeInterval?
    ) {
        for key in keys {
            guard let host = hosts[key] else { continue }
            let animation = CABasicAnimation(keyPath: "position")
            release.configure(animation)
            // Zero, for a slide Core Animation has not committed yet, starts now.
            animation.beginTime = beginTime ?? 0
            let end = origin(for: key, at: release.endPosition, placedNear: release.startPosition)
            animation.fromValue = NSValue(point: origin(for: key, at: release.startPosition))
            animation.toValue = NSValue(point: end)
            host.setFrameOrigin(end)
            host.layer?.add(animation, forKey: "position")
        }
    }

    /// The pages the running slide moves.
    private var slidingHosts: [BrowserSpaceRuntimeAssignment] {
        hosts.filter { $0.value.layer?.animationKeys()?.isEmpty == false }.map(\.key)
    }

    /// When Core Animation began the running slide, once it has committed it.
    private var slideBeginTime: CFTimeInterval? {
        hosts.values.lazy.compactMap { host -> CFTimeInterval? in
            guard let layer = host.layer, let key = layer.animationKeys()?.first else { return nil }
            return layer.animation(forKey: key)?.beginTime
        }.first { $0 > 0 }
    }

    private func stopAnimations() {
        if transition != nil {
            for host in hosts.values { host.layer?.removeAllAnimations() }
        }
        transition = nil
        preparedDestination = nil
    }

    private func prepareHosts(
        at position: CGFloat, destination: UUID?, refresh: Bool, preparesNeighbors: Bool = true
    ) {
        guard !spaces.isEmpty, let makeRoot else { return }
        let center = min(spaces.count - 1, max(0, Int(position.rounded())))
        let target = destination.flatMap { id in spaces.firstIndex { $0.id == id } } ?? center
        var visible = Set([Int(position.rounded(.down)), Int(position.rounded(.up)), target])
        if snapshot?.phase != .idle, let selected = spaces.firstIndex(where: { $0.id == selectedSpaceID }) {
            // A selection made mid-slide is where the slide goes next.
            visible.insert(selected)
        }
        let neighbors = preparesNeighbors ? [target - 1, target + 1, center - 1, center + 1] : []
        var indices = visible.filter { spaces.indices.contains($0) }
        for index in neighbors where indices.count < 4 && spaces.indices.contains(index) { indices.insert(index) }
        let cached = spaces.indices.filter { hosts[BrowserSpaceRuntimeAssignment(space: spaces[$0])] != nil }
            .sorted { abs($0 - target) < abs($1 - target) }
        for index in cached where indices.count < 4 { indices.insert(index) }
        let required = Set(indices.map { BrowserSpaceRuntimeAssignment(space: spaces[$0]) })
        for key in hosts.keys where !required.contains(key) {
            hosts.removeValue(forKey: key)?.removeFromSuperview()
        }
        for index in indices.sorted() {
            let space = spaces[index]
            let key = BrowserSpaceRuntimeAssignment(space: space)
            let contentPresentation = contentPresentation(at: index)
            if let host = hosts[key] {
                let previous = host.hostingView.rootView.contentPresentation
                if contentPresentation != .inactive, host.frame.size != bounds.size {
                    host.setFrameSize(bounds.size)
                }
                if previous == .inactive, contentPresentation != .inactive {
                    // Cached geometry may predate a sidebar resize. Restore
                    // the release origin before its native animation starts.
                    host.setFrameOrigin(origin(for: key, at: position))
                }
                var root = refresh ? makeRoot(space, space.id == selectedSpaceID) : host.hostingView.rootView
                root.contentPresentation = contentPresentation
                // A page off screen is hidden as well: on macOS 26, another
                // hosting view beside the selected page can take its clicks.
                host.isHidden = contentPresentation == .inactive
                if host.hostingView.rootView.content != root.content || previous != contentPresentation {
                    if contentPresentation != .interactive,
                        let responder = window?.firstResponder as? NSView, responder.isDescendant(of: host)
                    {
                        window?.makeFirstResponder(nil)
                    }
                    host.hostingView.rootView = root
                    if previous == .inactive, contentPresentation != .inactive {
                        // Admit the destination before moving its first frame
                        // into view, without refreshing roots on progress ticks.
                        host.hostingView.layoutSubtreeIfNeeded()
                    }
                }
            } else {
                var root = makeRoot(space, space.id == selectedSpaceID)
                root.contentPresentation = contentPresentation
                let host = SpacePageHost(root: root)
                host.frame = CGRect(origin: origin(for: key, at: position), size: bounds.size)
                host.hostingView.frame = host.bounds
                host.isHidden = contentPresentation == .inactive
                hosts[key] = host
                addSubview(host)
            }
        }
    }

    private func contentPresentation(at index: Int) -> SpaceContentPresentation {
        guard let snapshot else { return .inactive }
        let id = spaces[index].id
        if snapshot.phase == .idle {
            guard id == snapshot.destinationID else { return .inactive }
            return id == selectedSpaceID ? .interactive : .preview
        }
        // Keep the complete release path alive even as position samples advance
        // or a reversal carries the strip through an intermediate Space.
        let start = snapshot.transition?.startPosition ?? snapshot.position
        let end = snapshot.transition?.endPosition ?? snapshot.position
        let visible = Int(min(start, end).rounded(.down))...Int(max(start, end).rounded(.up))
        // A Space selected mid-slide is admitted with that selection, so the
        // slide carrying on to it doesn't wait on its first layout.
        return visible.contains(index) || id == snapshot.destinationID || id == selectedSpaceID ? .preview : .inactive
    }

    /// Where `key`'s page sits while the strip shows `position`, placed
    /// around the ends as near `reference`: a slide keeps each page where it
    /// began, so none switches ends partway.
    private func origin(
        for key: BrowserSpaceRuntimeAssignment, at position: CGFloat, placedNear reference: CGFloat? = nil
    ) -> CGPoint {
        let index = spaces.firstIndex { $0.id == key.spaceID } ?? 0
        let placed = SpacePagerInterpolation.index(index, near: reference ?? position, count: spaces.count)
        let direction: CGFloat = layoutDirection == .leftToRight ? 1 : -1
        return CGPoint(x: (CGFloat(placed) - position) * bounds.width * direction, y: 0)
    }

    private func needsMotion(_ host: NSView, to origin: CGPoint) -> Bool {
        host.frame.intersects(bounds) || CGRect(origin: origin, size: bounds.size).intersects(bounds)
    }

    private func positionHosts(at position: CGFloat) {
        for (key, host) in hosts {
            var origin = origin(for: key, at: position)
            if host.hostingView.rootView.contentPresentation == .inactive {
                guard host.frame.intersects(bounds) else { continue }
                // A wider viewport can expose a cached frame. Park it beyond
                // the clip until prepareHosts admits it to a visible slide.
                origin.x =
                    origin.x < 0 ? min(origin.x, -host.frame.width) : max(origin.x, bounds.maxX + host.frame.width)
            }
            if snapshot?.phase == .idle || needsMotion(host, to: origin) {
                if host.frame.origin != origin { host.setFrameOrigin(origin) }
            }
        }
    }

    private func updateAccessibility() {
        for (key, host) in hosts {
            host.setAccessibilityHidden(
                snapshot?.phase != .idle || snapshot?.destinationID != selectedSpaceID || key.spaceID != selectedSpaceID
            )
        }
    }
}
