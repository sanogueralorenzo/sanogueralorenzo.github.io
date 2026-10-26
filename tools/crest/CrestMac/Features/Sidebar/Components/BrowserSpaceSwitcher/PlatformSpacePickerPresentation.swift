import AppKit
import QuartzCore
import SwiftUI

/// Preserves the shared icon buttons while moving their highlight and native
/// scroll viewport with the page layers' actual presentation.
struct PlatformSpacePickerPresentation: NSViewRepresentable {
    let presentation: SpacePagerPresentation
    let style: CrestSpaceIconPickerStyle
    let spaces: [BrowserSpaceIdentity]
    let selectedSpaceID: UUID?
    let frames: [UUID: CGRect]
    let selectionTint: Color?

    func makeNSView(context: Context) -> SpacePickerPresentationView {
        SpacePickerPresentationView()
    }

    func updateNSView(_ view: SpacePickerPresentationView, context: Context) {
        view.update(
            presentation: presentation, style: style, spaces: spaces,
            selectedSpaceID: selectedSpaceID, frames: frames, selectionTint: selectionTint)
    }

    static func dismantleNSView(_ view: SpacePickerPresentationView, coordinator: ()) {
        view.disconnect()
    }
}

@MainActor
final class SpacePickerPresentationView: NSView {

    private let highlight = CAShapeLayer()
    private var presentation: SpacePagerPresentation?
    private var style = CrestSpaceIconPickerStyle.compact
    private weak var clipView: NSClipView?
    private var spaceIDs: [UUID] = []
    private var frames: [UUID: CGRect] = [:]
    private var colors: [UUID: NSColor] = [:]
    private var lastSnapshot: SpacePagerPresentation.Snapshot?
    private var scrollSegment: SpacePickerScrollProgress?
    private var activeTransition: SpacePagerSettlement?
    private var isObserving = false
    private var connectionScheduled = false
    private var lastViewportWidth: CGFloat = 0
    private var needsInitialPosition = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(highlight)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { return nil }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { disconnect() } else { connectSoon() }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil { disconnect() } else { connectSoon() }
    }

    override func layout() {
        super.layout()
        if let clipView, lastViewportWidth != clipView.bounds.width {
            lastViewportWidth = clipView.bounds.width
            needsInitialPosition = true
            if let snapshot = lastSnapshot, snapshot.phase == .idle {
                receive(snapshot)
            }
        }
    }

    func update(
        presentation: SpacePagerPresentation, style: CrestSpaceIconPickerStyle, spaces: [BrowserSpaceIdentity],
        selectedSpaceID: UUID?, frames: [UUID: CGRect], selectionTint: Color?
    ) {
        if self.presentation !== presentation {
            disconnect()
            self.presentation = presentation
        }
        self.style = style
        let ids = spaces.map(\.id)
        if spaceIDs != ids {
            lastSnapshot = nil
            scrollSegment = nil
            needsInitialPosition = true
        }
        spaceIDs = ids
        if self.frames != frames { needsInitialPosition = true }
        self.frames = frames
        colors = Dictionary(
            uniqueKeysWithValues: spaces.map {
                ($0.id, NSColor(selectionTint ?? $0.branding.primaryColor.color))
            })
        if let snapshot = presentation.snapshot, snapshot.spaceIDs == ids {
            receive(snapshot)
        } else if let selectedSpaceID, let index = ids.firstIndex(of: selectedSpaceID) {
            drawHighlight(at: CGFloat(index))
        }
        connectSoon()
    }

    private func connectSoon() {
        guard !connectionScheduled else { return }
        connectionScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            connectionScheduled = false
            guard window != nil, let scrollView = enclosingScrollView else { return }
            if clipView !== scrollView.contentView { needsInitialPosition = true }
            clipView = scrollView.contentView
            if !isObserving {
                isObserving = true
                presentation?.observe(owner: self) { [weak self] in self?.receive($0) }
            }
            if needsInitialPosition, let snapshot = presentation?.snapshot, snapshot.phase == .idle {
                receive(snapshot)
            }
        }
    }

    private func receive(_ snapshot: SpacePagerPresentation.Snapshot) {
        guard snapshot.spaceIDs == spaceIDs, snapshot.position.isFinite else { return }
        // Core Animation owns the complete release. Reinstalling from sampled
        // positions would turn a delayed callback into the visible catch-up jump.
        if let transition = snapshot.transition, activeTransition == transition { return }
        let previous = lastSnapshot
        lastSnapshot = snapshot
        let visibleScrollOffset =
            activeTransition == nil
            ? clipView?.bounds.minX : clipView?.layer?.presentation()?.bounds.minX ?? clipView?.bounds.minX
        highlight.removeAllAnimations()
        clipView?.layer?.removeAnimation(forKey: "spaceTransition.bounds.origin")
        activeTransition = nil
        if let visibleScrollOffset, snapshot.phase != .idle { scroll(to: visibleScrollOffset) }
        drawHighlight(at: snapshot.position)

        if snapshot.phase == .idle {
            if let scrollSegment, previous?.phase != .idle,
                snapshot.destinationID == scrollSegment.destinationID
            {
                advanceScroll(scrollSegment, position: snapshot.position)
                needsInitialPosition = false
            } else if needsInitialPosition || previous == nil || previous?.position != snapshot.position
                || previous?.phase != .idle
            {
                needsInitialPosition = true
                if let offset = centeredOffset(at: snapshot.position) {
                    scroll(to: offset)
                    needsInitialPosition = false
                }
            }
            scrollSegment = nil
            return
        }

        guard let destinationID = snapshot.destinationID,
            let destinationIndex = spaceIDs.firstIndex(of: destinationID),
            let clipView, let destinationOffset = centeredOffset(at: CGFloat(destinationIndex))
        else { return }
        if scrollSegment?.generation != snapshot.generation || scrollSegment?.phase != snapshot.phase
            || scrollSegment?.destinationID != destinationID
        {
            // Capture the real lane offset on interruption, release or reversal.
            // Manual overflow scrolling therefore cannot jump at gesture start.
            scrollSegment = SpacePickerScrollProgress(
                generation: snapshot.generation, phase: snapshot.phase, destinationID: destinationID,
                startPosition: previous.flatMap { $0.generation == snapshot.generation ? $0.position : nil }
                    ?? snapshot.position,
                destinationPosition: CGFloat(destinationIndex),
                startOffset: clipView.bounds.minX, destinationOffset: destinationOffset)
        }
        if let transition = snapshot.transition {
            if animateHighlight(transition) { activeTransition = transition }
            if let scrollSegment, let layer = clipView.layer {
                let start = NSValue(point: CGPoint(x: scrollSegment.startOffset, y: clipView.bounds.minY))
                let end = NSValue(point: CGPoint(x: scrollSegment.destinationOffset, y: clipView.bounds.minY))
                scroll(to: scrollSegment.destinationOffset)
                transition.animate(
                    layer, keyPath: "bounds.origin", values: [start, end], followsSpaceBoundaries: false)
            }
        } else if let scrollSegment {
            advanceScroll(scrollSegment, position: snapshot.position)
        }
    }

    private func animateHighlight(_ transition: SpacePagerSettlement) -> Bool {
        let frames = transition.positions.compactMap { interpolatedFrame(at: $0) }
        let colors = transition.positions.compactMap { interpolatedColor(at: $0) }
        guard frames.count == transition.positions.count, colors.count == frames.count else { return false }
        transition.animate(
            highlight, keyPath: "position", values: frames.map { NSValue(point: CGPoint(x: $0.midX, y: $0.midY)) })
        transition.animate(highlight, keyPath: "bounds.size", values: frames.map { NSValue(size: $0.size) })
        transition.animate(
            highlight, keyPath: "fillColor",
            values: colors.map {
                $0.withAlphaComponent($0.alphaComponent * CrestSpaceIconPickerMetrics.selectionFillOpacity).cgColor
            })
        transition.animate(highlight, keyPath: "strokeColor", values: colors.map(\.cgColor))
        return true
    }

    private func advanceScroll(_ segment: SpacePickerScrollProgress, position: CGFloat) {
        scroll(to: segment.offset(at: position))
    }

    private func centeredOffset(at position: CGFloat) -> CGFloat? {
        guard let clipView, let document = clipView.documentView,
            let frame = interpolatedFrame(at: position)
        else { return nil }
        let center = document.convert(CGPoint(x: frame.midX, y: frame.midY), from: self)
        let minimum = document.bounds.minX
        let maximum = max(minimum, document.bounds.maxX - clipView.bounds.width)
        return min(maximum, max(minimum, center.x - clipView.bounds.width / 2))
    }

    private func scroll(to offset: CGFloat) {
        guard let clipView, abs(clipView.bounds.minX - offset) > 0.001 else { return }
        clipView.scroll(to: CGPoint(x: offset, y: clipView.bounds.minY))
        clipView.enclosingScrollView?.reflectScrolledClipView(clipView)
    }

    private func drawHighlight(at position: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let frame = interpolatedFrame(at: position), let color = interpolatedColor(at: position) else {
            highlight.isHidden = true
            return
        }
        highlight.isHidden = false
        highlight.frame = frame
        let stroke = CrestLayout.hairline
        highlight.path =
            CrestSpaceIconPickerShape(style: style)
            .inset(by: stroke / 2)
            .path(in: CGRect(origin: .zero, size: frame.size))
            .cgPath
        highlight.fillColor =
            color.withAlphaComponent(
                color.alphaComponent * CrestSpaceIconPickerMetrics.selectionFillOpacity
            ).cgColor
        highlight.strokeColor = color.cgColor
        highlight.lineWidth = stroke
    }

    private func interpolation(at position: CGFloat) -> (UUID, UUID, CGFloat)? {
        guard let sample = SpacePagerInterpolation(position: position, count: spaceIDs.count) else { return nil }
        return (spaceIDs[sample.lower], spaceIDs[sample.upper], sample.fraction)
    }

    private func interpolatedFrame(at position: CGFloat) -> CGRect? {
        guard let sample = SpacePagerInterpolation(position: position, count: spaceIDs.count),
            let start = frames[spaceIDs[sample.lower]], let end = frames[spaceIDs[sample.upper]],
            start.width > 0, start.height > 0, end.width > 0, end.height > 0
        else { return nil }
        return sample.frame(from: start, to: end)
    }

    private func interpolatedColor(at position: CGFloat) -> NSColor? {
        guard let (lower, upper, fraction) = interpolation(at: position),
            let start = colors[lower]?.usingColorSpace(.deviceRGB),
            let end = colors[upper]?.usingColorSpace(.deviceRGB)
        else { return nil }
        return NSColor(
            red: start.redComponent + (end.redComponent - start.redComponent) * fraction,
            green: start.greenComponent + (end.greenComponent - start.greenComponent) * fraction,
            blue: start.blueComponent + (end.blueComponent - start.blueComponent) * fraction,
            alpha: start.alphaComponent + (end.alphaComponent - start.alphaComponent) * fraction)
    }

    func disconnect() {
        presentation?.removeObserver(owner: self)
        isObserving = false
        clipView?.layer?.removeAnimation(forKey: "spaceTransition.bounds.origin")
        clipView = nil
        scrollSegment = nil
        activeTransition = nil
        highlight.removeAllAnimations()
        lastViewportWidth = 0
        needsInitialPosition = true
    }
}
