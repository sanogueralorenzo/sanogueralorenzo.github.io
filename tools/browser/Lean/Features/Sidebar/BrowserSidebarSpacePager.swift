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
        interactionLocked = store.owner.sidebarDrag.payload != nil
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
    private var hosts: [UUID: NSHostingView<BrowserSidebarSpaceRoot>] = [:]
    private(set) var selectedSpaceID: UUID?
    private(set) var isMoving = false
    private var epoch = 0
    private var lastSize = CGSize.zero
    private weak var store: BrowserStore?
    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        clipsToBounds = true
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { isMoving ? nil : super.hitTest(point) }

    func update(
        store: BrowserStore, spaces: [BrowserSpace], selectedSpaceID id: UUID, step: Int?, interactionLocked: Bool,
        reduceMotion: Bool, layoutDirection: LayoutDirection
    ) {
        self.store = store
        let previous = selectedSpaceID
        let changed = previous != id
        let valid = Set(spaces.map(\.id))
        for key in hosts.keys where !valid.contains(key) { hosts.removeValue(forKey: key)?.removeFromSuperview() }
        let canSlide =
            changed && previous != nil && previous.map(valid.contains) == true
            && !reduceMotion && !interactionLocked && step != nil
            && bounds.width > 0
        if changed || (isMoving && (reduceMotion || interactionLocked)) {
            stopAtPresentationPositions()
        }
        // Existing roots keep their native scroll view and local SwiftUI state.
        for space in spaces where hosts[space.id] != nil || space.id == id {
            let root = BrowserSidebarSpaceRoot(store: store, spaceID: space.id)
            if let host = hosts[space.id] {
                if canSlide, space.id == id, host.isHidden {
                    let direction: CGFloat = (step ?? 1) > 0 ? 1 : -1
                    host.frame = bounds.offsetBy(
                        dx: direction * bounds.width * (layoutDirection == .leftToRight ? 1 : -1), dy: 0)
                }
            } else {
                let host = NSHostingView(rootView: root)
                host.identifier = NSUserInterfaceItemIdentifier(space.id.uuidString)
                host.sizingOptions = []
                host.safeAreaRegions = []
                host.wantsLayer = true
                let direction: CGFloat = (step ?? 1) > 0 ? 1 : -1
                host.frame = bounds.offsetBy(
                    dx: canSlide ? direction * bounds.width * (layoutDirection == .leftToRight ? 1 : -1) : 0, dy: 0)
                hosts[space.id] = host
                addSubview(host)
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

    private func stopAtPresentationPositions() {
        epoch += 1
        for host in hosts.values {
            let origin = host.layer?.presentation()?.frame.origin ?? host.frame.origin
            host.layer?.removeAllAnimations()
            host.setFrameOrigin(origin)
        }
        isMoving = false
    }

    private func animate(from origin: UUID, to destination: UUID, step: Int, layoutDirection: LayoutDirection) {
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
        stopAtPresentationPositions()
        for host in hosts.values { host.setFrameSize(bounds.size) }
        settle()
    }

    func disconnect() {
        stopAtPresentationPositions()
        for host in hosts.values { host.removeFromSuperview() }
        hosts.removeAll()
        store?.sidebarSpaceTransitioning = false
        store = nil
    }
}
