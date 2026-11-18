import AppKit
import QuartzCore
import SwiftUI

extension EnvironmentValues {
    @Entry var sidebarSpaceID: UUID?
}

extension BrowserStore {
    func sidebarSpace(_ id: UUID?) -> BrowserSpace {
        id.flatMap { value in session.spaces.first { $0.id == value } } ?? activeSpace
    }

    func sidebarSelectedTabID(in space: BrowserSpace) -> UUID? {
        windowState.emptySpaces.contains(space.id) ? nil : windowState.tabsBySpace[space.id] ?? space.selectedTabID
    }
}

/// Crest's native page motion, scoped to the sidebar's window presentation.
struct BrowserSidebarSpacePager: NSViewRepresentable {
    let store: BrowserStore
    let spaces: [BrowserSpace]
    let selectedSpaceID: UUID
    let step: Int?
    let interactionLocked: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    init(store: BrowserStore) {
        self.store = store
        spaces = store.session.spaces
        selectedSpaceID = store.activeSpace.id
        step = store.sidebarSpaceStep
        interactionLocked = store.isClosed || store.owner.sidebarDrag.payload != nil
    }

    func makeNSView(context: Context) -> BrowserSidebarSpaceViewport { BrowserSidebarSpaceViewport() }

    func updateNSView(_ view: BrowserSidebarSpaceViewport, context: Context) {
        view.update(
            store: store, spaces: spaces, selectedSpaceID: selectedSpaceID, step: step,
            interactionLocked: interactionLocked, reduceMotion: reduceMotion, layoutDirection: layoutDirection)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: BrowserSidebarSpaceViewport, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: .zero)
    }

    static func dismantleNSView(_ view: BrowserSidebarSpaceViewport, coordinator: ()) { view.disconnect() }
}

private struct BrowserSidebarSpaceRoot: View {
    let store: BrowserStore
    let spaceID: UUID
    var body: some View {
        if let space = store.session.spaces.first(where: { $0.id == spaceID }) {
            BrowserSidebarSpacePage(store: store, space: space)
                .environment(\.sidebarSpaceID, spaceID)
                .allowsHitTesting(spaceID == store.activeSpace.id && !store.sidebarSpaceTransitioning)
                .accessibilityHidden(spaceID != store.activeSpace.id || store.sidebarSpaceTransitioning)
        }
    }
}

@MainActor
final class BrowserSidebarSpaceViewport: NSView {
    private struct Motion {
        let origin: UUID
        let initialOffset: CGFloat
        var offset: CGFloat
        var translation: CGFloat = 0
        var direction: CGFloat = 0
        var target: UUID?
        var step = 0
    }
    private var hosts: [UUID: NSHostingView<BrowserSidebarSpaceRoot>] = [:]
    private(set) var selectedSpaceID: UUID?
    private(set) var isMoving = false
    private var epoch = 0
    private var lastSize = CGSize.zero
    private weak var store: BrowserStore?
    private var motion: Motion?
    private var spaceIDs: [UUID] = []
    private(set) var reduceMotion = false
    private(set) var rightToLeft = false
    private var interactionLocked = false
    private lazy var gesture = BrowserSpaceSwipeGesture(viewport: self)
    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        clipsToBounds = true
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { isMoving ? self : super.hitTest(point) }

    func update(
        store: BrowserStore, spaces: [BrowserSpace], selectedSpaceID id: UUID, step: Int?, interactionLocked: Bool,
        reduceMotion: Bool, layoutDirection: LayoutDirection
    ) {
        if self.store !== store, self.store?.sidebarSpaceViewport === self { self.store?.sidebarSpaceViewport = nil }
        self.store = store
        store.sidebarSpaceViewport = self
        let previous = selectedSpaceID
        let changed = previous != id
        let ids = spaces.map(\.id)
        let rtl = layoutDirection == .rightToLeft
        if motion != nil && (changed || spaceIDs != ids || interactionLocked || reduceMotion || rightToLeft != rtl) {
            gesture.cancelCurrentGesture()
            stopAtPresentationPositions()
        }
        self.spaceIDs = ids
        self.reduceMotion = reduceMotion
        self.rightToLeft = rtl
        self.interactionLocked = interactionLocked
        let valid = Set(spaces.map(\.id))
        for key in hosts.keys where !valid.contains(key) { hosts.removeValue(forKey: key)?.removeFromSuperview() }
        if motion != nil { return }
        let canSlide =
            changed && previous != nil && previous.map(valid.contains) == true
            && !reduceMotion && !interactionLocked && step != nil
            && bounds.width > 0
        if changed || (isMoving && (reduceMotion || interactionLocked)) {
            gesture.cancelCurrentGesture()
            stopAtPresentationPositions()
        }
        // Existing roots keep their native scroll view and local SwiftUI state.
        for space in spaces where hosts[space.id] != nil || space.id == id {
            if let host = hosts[space.id] {
                if canSlide, space.id == id, host.isHidden {
                    let direction: CGFloat = (step ?? 1) > 0 ? 1 : -1
                    host.frame = bounds.offsetBy(
                        dx: direction * bounds.width * (layoutDirection == .leftToRight ? 1 : -1), dy: 0)
                }
            } else {
                let host = prepareHost(space.id, store: store)
                let direction: CGFloat = (step ?? 1) > 0 ? 1 : -1
                host.frame = bounds.offsetBy(
                    dx: canSlide ? direction * bounds.width * (layoutDirection == .leftToRight ? 1 : -1) : 0, dy: 0)
            }
        }
        selectedSpaceID = id
        var required: Set<UUID> = [id]
        if let previous, hosts[previous] != nil { required.insert(previous) }
        prune(retaining: required)
        if changed {
            if canSlide {
                animate(from: previous!, to: id, step: step!, layoutDirection: layoutDirection)
            } else {
                settle()
            }
        } else if !isMoving {
            settle()
        }
    }

    private func prepareHost(_ id: UUID, store: BrowserStore) -> NSHostingView<BrowserSidebarSpaceRoot> {
        if let host = hosts[id] { return host }
        let host = NSHostingView(rootView: BrowserSidebarSpaceRoot(store: store, spaceID: id))
        host.identifier = NSUserInterfaceItemIdentifier(id.uuidString)
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.wantsLayer = true
        host.frame = bounds
        hosts[id] = host
        addSubview(host)
        return host
    }

    func handleScroll(_ event: NSEvent, isInside: Bool, enabled: Bool) -> NSEvent? {
        gesture.handle(event, isInside: isInside, enabled: enabled && !interactionLocked)
    }

    func beginInteractiveMotion() -> Int? {
        guard let store, !store.isClosed, !interactionLocked, !reduceMotion,
            window != nil, !isHiddenOrHasHiddenAncestor, bounds.width > 0, spaceIDs.count > 1
        else { return nil }
        stopAtPresentationPositions()
        guard
            let origin = hosts.filter({ !$0.value.isHidden }).min(by: {
                abs($0.value.frame.minX - bounds.minX) < abs($1.value.frame.minX - bounds.minX)
            })
        else { return nil }
        let offset = origin.value.frame.minX - bounds.minX
        motion = Motion(origin: origin.key, initialOffset: offset, offset: offset)
        isMoving = true
        store.sidebarSpaceTransitioning = true
        return epoch
    }

    func updateInteractiveMotion(deltaX: CGFloat, token: Int) -> Bool {
        guard token == epoch, deltaX.isFinite, var current = motion, let store,
            !store.isClosed, !interactionLocked, window != nil
        else { return false }
        if current.direction == 0, deltaX != 0 {
            current.direction = deltaX < 0 ? -1 : 1
            current.step = (deltaX < 0 ? 1 : -1) * (rightToLeft ? -1 : 1)
            guard let index = spaceIDs.firstIndex(of: current.origin) else { return false }
            current.target = spaceIDs[(index + current.step + spaceIDs.count) % spaceIDs.count]
            _ = prepareHost(current.target!, store: store)
        }
        let available = max(0, bounds.width - current.initialOffset * current.direction)
        let travel = min(available, max(0, (current.translation + deltaX) * current.direction))
        current.translation = travel * current.direction
        current.offset = current.initialOffset + current.translation
        motion = current
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (id, host) in hosts {
            host.isHidden = id != current.origin && id != current.target
            if id == current.origin { host.frame = bounds.offsetBy(dx: current.offset, dy: 0) }
            if id == current.target {
                host.frame = bounds.offsetBy(dx: current.offset - current.direction * bounds.width, dy: 0)
            }
        }
        CATransaction.commit()
        var required: Set<UUID> = [current.origin]
        if let target = current.target { required.insert(target) }
        if let selectedSpaceID { required.insert(selectedSpaceID) }
        prune(retaining: required)
        return true
    }

    func endInteractiveMotion(velocity: CGFloat, cancelled: Bool, token: Int) {
        guard token == epoch, let current = motion else { return }
        let travel = max(0, current.translation * current.direction)
        let projection =
            max(travel, current.offset * current.direction)
            + (cancelled || travel == 0 || !velocity.isFinite ? 0 : velocity * current.direction * 0.15)
        let completes = !cancelled && travel > 0 && projection >= bounds.width / 2
        animate(
            from: current.origin, to: completes ? current.target ?? current.origin : current.origin,
            step: current.step, layoutDirection: rightToLeft ? .rightToLeft : .leftToRight,
            commitSelection: true)
    }

    func cancelInteractiveMotion() {
        guard motion != nil else { return }
        stopAtPresentationPositions()
        settle()
    }

    func stepSpace(_ step: Int) { store?.adjacentSpace(step) }

    private func stopAtPresentationPositions() {
        epoch += 1
        for host in hosts.values {
            let origin = host.layer?.presentation()?.frame.origin ?? host.frame.origin
            host.layer?.removeAllAnimations()
            host.setFrameOrigin(origin)
        }
        isMoving = false
        motion = nil
    }

    private func animate(
        from origin: UUID, to destination: UUID, step: Int, layoutDirection: LayoutDirection,
        commitSelection: Bool = false
    ) {
        isMoving = true
        let token = epoch
        let direction: CGFloat = (step > 0 ? 1 : -1) * (layoutDirection == .leftToRight ? 1 : -1)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.27, 1, 0.18, 1)
            for (id, host) in hosts {
                guard !host.isHidden || id == origin || id == destination else { continue }
                host.isHidden = false
                let x: CGFloat =
                    id == destination
                    ? 0
                    : id == origin ? -direction * bounds.width : (host.frame.minX < 0 ? -bounds.width : bounds.width)
                host.animator().setFrameOrigin(CGPoint(x: x, y: 0))
            }
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.epoch == token else { return }
                self.motion = nil
                if commitSelection, let store = self.store, !store.isClosed {
                    self.selectedSpaceID = destination
                    store.selectSpace(destination, step: step)
                    self.selectedSpaceID = store.activeSpace.id
                }
                self.settle()
            }
        }
    }

    private func settle() {
        isMoving = false
        for (id, host) in hosts {
            let hidden = id != selectedSpaceID
            if host.isHidden != hidden { host.isHidden = hidden }
            if !hidden, host.frame != bounds { host.frame = bounds }
        }
        if let selectedSpaceID { prune(retaining: [selectedSpaceID]) }
        Task { @MainActor [weak self] in
            guard let self, !self.isMoving else { return }
            if self.store?.sidebarSpaceTransitioning == true { self.store?.sidebarSpaceTransitioning = false }
        }
    }

    /// Also bounds roots during repeated interruptions, before any completion runs.
    private func prune(retaining required: Set<UUID>) {
        guard let store, let selectedSpaceID,
            let index = store.session.spaces.firstIndex(where: { $0.id == selectedSpaceID })
        else { return }
        let indices = Dictionary(
            uniqueKeysWithValues: store.session.spaces.enumerated().map { ($0.element.id, $0.offset) })
        let spare = hosts.keys.filter { !required.contains($0) }.sorted {
            abs((indices[$0] ?? index) - index) < abs((indices[$1] ?? index) - index)
        }.prefix(max(0, 4 - required.count))
        let keep = required.union(spare)
        for id in hosts.keys where !keep.contains(id) { hosts.removeValue(forKey: id)?.removeFromSuperview() }
    }

    override func layout() {
        super.layout()
        guard lastSize != bounds.size else { return }
        lastSize = bounds.size
        gesture.cancelCurrentGesture()
        stopAtPresentationPositions()
        for host in hosts.values { host.setFrameSize(bounds.size) }
        settle()
    }

    func disconnect() {
        gesture.cancelCurrentGesture()
        stopAtPresentationPositions()
        for host in hosts.values { host.removeFromSuperview() }
        hosts.removeAll()
        store?.sidebarSpaceTransitioning = false
        if store?.sidebarSpaceViewport === self { store?.sidebarSpaceViewport = nil }
        store = nil
    }
}
