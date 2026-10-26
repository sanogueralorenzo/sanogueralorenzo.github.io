import AppKit
import QuartzCore
import SwiftUI

/// Backgrounds share both the pager's tracked position and its release timeline
/// without making the shell observe every gesture sample.
struct SpaceBackdropBlend<Background: View>: NSViewRepresentable {
    let spaces: [SpaceModel]
    let selectedSpace: SpaceModel?
    @ViewBuilder let background: (SpaceModel?) -> Background

    func makeNSView(context: Context) -> SpaceBackdropBlendView<Background> {
        SpaceBackdropBlendView(frame: .zero)
    }

    func updateNSView(_ view: SpaceBackdropBlendView<Background>, context: Context) {
        let environment = context.environment
        view.update(
            spaces: spaces, selectedSpace: selectedSpace,
            presentation: environment.spacePagerPresentation
        ) {
            SpaceBackdropRoot(background: background($0))
        }
    }

    static func dismantleNSView(_ view: SpaceBackdropBlendView<Background>, coordinator: ()) {
        view.disconnect()
    }
}

struct SpaceBackdropRoot<Background: View>: View {
    let background: Background

    var body: some View {
        background
            .transaction { $0.disablesAnimations = true }
    }
}

@MainActor
final class SpaceBackdropBlendView<Background: View>: NSView {
    private var presentation: SpacePagerPresentation?
    private var spaces: [SpaceModel] = []
    private var selectedSpace: SpaceModel?
    private var makeRoot: ((SpaceModel?) -> SpaceBackdropRoot<Background>)?
    private var hosts: [BrowserSpaceRuntimeAssignment: NSHostingView<SpaceBackdropRoot<Background>>] = [:]
    private var fallback: NSHostingView<SpaceBackdropRoot<Background>>?
    private var activeTransition: SpacePagerSettlement?
    /// The background on top while nothing moves, or nil while a slide or a
    /// swipe shows more than one.
    private var restingKey: BrowserSpaceRuntimeAssignment?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = true
        setAccessibilityElement(false)
        setAccessibilityHidden(true)
    }

    required init?(coder: NSCoder) { return nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func layout() {
        super.layout()
        sizeShownHosts()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        sizeShownHosts()
    }

    func update(
        spaces: [SpaceModel], selectedSpace: SpaceModel?,
        presentation: SpacePagerPresentation?,
        makeRoot: @escaping (SpaceModel?) -> SpaceBackdropRoot<Background>
    ) {
        let connectionChanged = self.presentation !== presentation
        if connectionChanged { disconnect() }
        self.spaces = spaces
        self.selectedSpace = selectedSpace
        self.makeRoot = makeRoot
        self.presentation = presentation

        let valid = Set(spaces.map(BrowserSpaceRuntimeAssignment.init(space:)))
        for key in hosts.keys where !valid.contains(key) {
            hosts.removeValue(forKey: key)?.removeFromSuperview()
        }
        // SwiftUI supplies new appearance/accessibility settings on semantic
        // updates. Progress callbacks below only change layer opacity.
        for space in spaces {
            hosts[BrowserSpaceRuntimeAssignment(space: space)]?.rootView = makeRoot(space)
        }
        if spaces.isEmpty {
            if let fallback {
                fallback.rootView = makeRoot(selectedSpace)
            } else {
                fallback = addHost(root: makeRoot(selectedSpace))
            }
        } else {
            fallback?.removeFromSuperview()
            fallback = nil
        }
        if connectionChanged {
            presentation?.observe(owner: self) { [weak self] in self?.receive($0) }
        }
        receive(presentation?.snapshot)
    }

    func disconnect() {
        presentation?.removeObserver(owner: self)
        presentation = nil
        activeTransition = nil
        for host in hosts.values { host.layer?.removeAnimation(forKey: "spaceTransition.opacity") }
    }

    private func receive(_ snapshot: SpacePagerPresentation.Snapshot?) {
        guard !spaces.isEmpty, let makeRoot else { return }
        if let transition = snapshot?.transition, activeTransition == transition { return }
        let transition = snapshot?.spaceIDs == spaces.map(\.id) ? snapshot?.transition : nil
        activeTransition = transition
        let count = spaces.count
        // A step around the ends of the Spaces runs up to one Space past either end.
        let reach: CGFloat = count > 2 ? 1 : 0
        let position: CGFloat
        if let snapshot, snapshot.spaceIDs == spaces.map(\.id), snapshot.position.isFinite {
            position = min(CGFloat(count - 1) + reach, max(-reach, snapshot.position))
        } else {
            position = CGFloat(spaces.firstIndex { $0.id == selectedSpace?.id } ?? 0)
        }
        let center = Int(position.rounded())
        let destination = transition?.endPosition ?? position
        let lowest = min(center - 1, Int(destination.rounded(.down)))
        let highest = max(center + 1, Int(destination.rounded(.up)))
        let wraps = count > 2 && [position, destination].contains { $0 < 0 || $0 > CGFloat(count - 1) }
        let range =
            wraps
            ? Set((max(-1, lowest)...min(count, highest)).map { ($0 + count) % count })
            : Set(max(0, lowest)...min(count - 1, highest))
        let required = Set(range.map { BrowserSpaceRuntimeAssignment(space: spaces[$0]) })
        let isResting = transition == nil && position == position.rounded()
        restingKey = isResting ? BrowserSpaceRuntimeAssignment(space: spaces[(center % count + count) % count]) : nil
        // Keep the two visible backgrounds and their neighbors ready. No tab
        // trees, page snapshots, or WebKit instances belong to these hosts.
        for index in range.sorted() {
            let space = spaces[index]
            let key = BrowserSpaceRuntimeAssignment(space: space)
            if hosts[key] == nil { hosts[key] = addHost(root: makeRoot(space)) }
        }
        if hosts.count > 4 {
            for key in hosts.keys where !required.contains(key) {
                hosts.removeValue(forKey: key)?.removeFromSuperview()
            }
        }
        if !isResting {
            for host in hosts.values where host.frame != bounds { host.frame = bounds }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, space) in spaces.enumerated() {
            guard let layer = hosts[BrowserSpaceRuntimeAssignment(space: space)]?.layer else { continue }
            // Stable stacking also works when an interrupted slide crosses a
            // third Space. The lower background remains opaque at all times.
            // Around the ends, the Space a step reaches stacks past the other.
            let placed = SpacePagerInterpolation.index(
                index, near: transition?.startPosition ?? position, count: count)
            layer.zPosition = CGFloat(placed)
            if let transition {
                transition.animate(
                    layer, keyPath: "opacity",
                    values: transition.positions.map {
                        SpacePagerInterpolation.backdropOpacity(at: $0, index: placed)
                    })
            } else {
                layer.removeAnimation(forKey: "spaceTransition.opacity")
                layer.opacity = SpacePagerInterpolation.backdropOpacity(at: position, index: placed)
            }
        }
        CATransaction.commit()
    }

    /// Only the background on screen follows a live resize. The ones under it
    /// and beyond it are sized when a slide is about to show them.
    private func sizeShownHosts() {
        for (key, host) in hosts where host.frame != bounds && (restingKey == nil || key == restingKey) {
            host.frame = bounds
        }
        if let fallback, fallback.frame != bounds { fallback.frame = bounds }
    }

    private func addHost(root: SpaceBackdropRoot<Background>) -> NSHostingView<SpaceBackdropRoot<Background>> {
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.wantsLayer = true
        host.layer?.opacity = 0
        host.frame = bounds
        addSubview(host)
        host.layer?.opacity = 1
        return host
    }
}
