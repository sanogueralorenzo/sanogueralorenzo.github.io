import AppKit

@MainActor
private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A mouse-operated companion to the keyboard-accessible native action menu.
@MainActor
final class SelectionToolbar: NSObject {
    var onChoose: ((EditAction) -> Void)?
    var onDismiss: (() -> Void)?
    let panel: NSPanel

    override init() {
        panel = SelectionPanel(contentRect: NSRect(x: 0, y: 0, width: 370, height: 110),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = "Rewrite selection"; panel.setAccessibilityLabel("Rewrite selection")
        panel.level = .floating; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        let background = NSVisualEffectView(frame: panel.contentView!.bounds)
        background.material = .popover; background.state = .active; background.wantsLayer = true
        background.layer?.cornerRadius = 12; background.layer?.masksToBounds = true
        panel.contentView = background
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false; background.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -8)])
        let title = NSTextField(labelWithString: "Rewrite"); title.font = .systemFont(ofSize: 11, weight: .semibold)
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss rewrite toolbar")!, target: self, action: #selector(dismiss))
        close.isBordered = false; close.toolTip = "Dismiss (Esc)"; close.setAccessibilityLabel("Dismiss rewrite toolbar")
        let heading = NSStackView(views: [title, spacer, close]); stack.addArrangedSubview(heading)
        heading.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        for actions in [Array(EditAction.allCases.prefix(3)), Array(EditAction.allCases.suffix(3))] {
            let row = NSStackView(); row.spacing = 6
            for action in actions {
                let button = NSButton(title: action.rawValue, target: self, action: #selector(choose(_:)))
                button.bezelStyle = .rounded; button.controlSize = .small
                button.tag = EditAction.allCases.firstIndex(of: action)!
                button.setAccessibilityLabel(action.rawValue); row.addArrangedSubview(button)
            }
            stack.addArrangedSubview(row)
        }
        background.layoutSubtreeIfNeeded()
        panel.setContentSize(NSSize(width: max(340, stack.fittingSize.width + 24), height: stack.fittingSize.height + 16))
    }
    func show(at point: NSPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
        let bounds = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        panel.setFrameTopLeftPoint(NSPoint(x: min(max(point.x, bounds.minX), bounds.maxX - panel.frame.width),
            y: max(min(point.y, bounds.maxY), bounds.minY + panel.frame.height)))
        panel.orderFrontRegardless()
    }
    func hide() { panel.orderOut(nil) }
    @objc private func dismiss() { onDismiss?() }
    @objc private func choose(_ sender: NSButton) { onChoose?(EditAction.allCases[sender.tag]) }
}

/// Polls only the foreground selection; never copies text or posts input events.
/// Two matching samples keep the toolbar out of an in-progress selection gesture.
@MainActor
final class SelectionWatcher {
    var isEnabled: () -> Bool = { true }
    var onSelection: ((CapturedSelection) -> Void)?
    var onHide: (() -> Void)?
    weak var interactionWindow: NSWindow?
    private let capture: @MainActor () -> CapturedSelection?
    private var timer: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var candidate: CapturedSelection?
    private var presented = false
    private var dismissed = false

    init(capture: @escaping @MainActor () -> CapturedSelection? = { try? CapturedSelection.capture(timeout: 0.15) }) {
        self.capture = capture
    }
    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.1; self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                if event.type == .keyDown || event.window !== self?.interactionWindow { self?.dismiss() }
            }
            return event
        }
    }
    func stop() {
        timer?.invalidate(); timer = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil; reset()
    }
    func dismiss() { dismissed = true; presented = false; onHide?() }
    private func reset() {
        candidate = nil; dismissed = false; presented = false; onHide?()
    }
    private func poll() {
        guard isEnabled() else { dismiss(); return }
        guard NSEvent.pressedMouseButtons == 0, NSEvent.modifierFlags.intersection([.shift, .command, .control, .option]).isEmpty else { return }
        guard let current = capture() else { reset(); return }
        if let candidate, candidate.matches(current) {
            // An observed change away and back must not resurrect a stale capture.
            guard !candidate.invalidated else { dismiss(); return }
            if !dismissed && !presented { presented = true; onSelection?(candidate) }
        } else {
            onHide?(); candidate = current; presented = false; dismissed = false
        }
    }
}
