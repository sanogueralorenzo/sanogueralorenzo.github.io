import AppKit

@MainActor
final class RewritePanel: NSPanel {
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() }
        else if event.keyCode == 36 || event.keyCode == 76 { onReturn?() }
        else { super.keyDown(with: event) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if [53, 36, 76].contains(event.keyCode), event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty { keyDown(with: event); return true }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class Preview: NSObject, NSWindowDelegate {
    var onReplace: (() -> Void)?
    var onCopy: (() -> Void)?
    var onCancel: (() -> Void)?
    private(set) var panel: RewritePanel!
    private let title = NSTextField(labelWithString: "Rewrite")
    private let result = NSTextView()
    private let original = NSTextView()
    private let originalScroll = NSScrollView()
    private let resultScroll = NSScrollView()
    private let note = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()
    private let compare = NSButton(checkboxWithTitle: "Show original", target: nil, action: nil)
    private let replace = NSButton(title: "Replace", target: nil, action: nil)
    private let copy = NSButton(title: "Copy", target: nil, action: nil)
    private let cancel = NSButton(title: "Cancel", target: nil, action: nil)
    private var resultHeight: NSLayoutConstraint!

    override init() {
        super.init()
        panel = RewritePanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 310), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Rewrite"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.level = .floating; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        panel.onReturn = { [weak self] in if self?.replace.isEnabled == true { self?.onReplace?() } }
        panel.onEscape = { [weak self] in self?.onCancel?() }
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor), stack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor), stack.topAnchor.constraint(equalTo: panel.contentView!.topAnchor), stack.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor)])
        let heading = NSStackView(views: [title, spinner]); heading.spacing = 8
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        spinner.widthAnchor.constraint(equalToConstant: 14).isActive = true; spinner.heightAnchor.constraint(equalToConstant: 14).isActive = true
        stack.addArrangedSubview(heading)
        configureText(result, in: resultScroll); configureText(original, in: originalScroll)
        result.setAccessibilityLabel("Rewritten text"); original.setAccessibilityLabel("Original text")
        for scroll in [resultScroll, originalScroll] {
            stack.addArrangedSubview(scroll); scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        }
        resultHeight = resultScroll.heightAnchor.constraint(equalToConstant: 64); resultHeight.isActive = true
        originalScroll.heightAnchor.constraint(equalToConstant: 90).isActive = true
        compare.target = self; compare.action = #selector(toggleOriginal)
        stack.addArrangedSubview(compare)
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor
        stack.addArrangedSubview(note); note.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [cancel, spacer, copy, replace]); buttons.spacing = 8
        stack.addArrangedSubview(buttons); buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        for (button, selector) in [(replace, #selector(replaceClicked)), (copy, #selector(copyClicked)), (cancel, #selector(cancelClicked))] {
            button.bezelStyle = .rounded; button.target = self; button.action = selector
        }
        replace.keyEquivalent = "\r"; cancel.keyEquivalent = "\u{1b}"
        copy.keyEquivalent = "c"; copy.keyEquivalentModifierMask = [.command, .shift]
    }
    func processing(action: EditAction, original text: String, point: NSPoint, provider: String) {
        title.stringValue = action.rawValue; original.string = text; result.string = ""
        originalScroll.isHidden = true; resultScroll.isHidden = true
        compare.state = .off; compare.isHidden = true; copy.isHidden = true; replace.isHidden = true; replace.isEnabled = false
        note.stringValue = "Rewriting with \(provider)…"; spinner.startAnimation(nil)
        show(at: point)
    }
    func showResult(_ text: String, limitation: String?) {
        spinner.stopAnimation(nil); result.string = text; resultScroll.isHidden = false
        if let container = result.textContainer, let layout = result.layoutManager {
            layout.ensureLayout(for: container)
            resultHeight.constant = min(220, max(64, layout.usedRect(for: container).height + 16))
        }
        compare.isHidden = false; copy.isHidden = false; replace.isHidden = false; replace.isEnabled = limitation == nil
        note.stringValue = limitation ?? "Return to replace · Esc to cancel"
        resize(); panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(replace.isEnabled ? replace : copy)
    }
    func message(_ text: String, at point: NSPoint = NSEvent.mouseLocation) {
        title.stringValue = "Rewrite"; spinner.stopAnimation(nil); result.string = ""; original.string = ""
        resultScroll.isHidden = true; originalScroll.isHidden = true; compare.isHidden = true
        copy.isHidden = true; replace.isHidden = true; replace.isEnabled = false
        note.stringValue = text; show(at: point)
    }
    func limitation(_ message: String) { note.stringValue = message; replace.isEnabled = false; resize() }
    func close() { panel.orderOut(nil); spinner.stopAnimation(nil); result.string = ""; original.string = "" }
    func windowShouldClose(_ sender: NSWindow) -> Bool { onCancel?(); return false }
    private func show(at point: NSPoint) {
        resize()
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main!
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        panel.setFrameTopLeftPoint(NSPoint(x: min(max(point.x, visible.minX), visible.maxX - panel.frame.width),
                                          y: max(min(point.y, visible.maxY), visible.minY + panel.frame.height)))
        NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(cancel)
    }
    private func resize() {
        panel.contentView?.layoutSubtreeIfNeeded()
        let height: CGFloat = 126 + (resultScroll.isHidden ? 0 : resultHeight.constant + 40) + (originalScroll.isHidden ? 0 : 102) + (note.stringValue.count > 85 ? 20 : 0)
        let top = panel.frame.maxY; panel.setContentSize(NSSize(width: 420, height: height))
        var frame = panel.frame; frame.origin.y = top - frame.height; panel.setFrame(frame, display: true)
    }
    private func configureText(_ text: NSTextView, in scroll: NSScrollView) {
        text.isEditable = false; text.isSelectable = true; text.isRichText = false
        text.font = .systemFont(ofSize: 13); text.textColor = .labelColor; text.drawsBackground = false
        text.textContainerInset = NSSize(width: 2, height: 5)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
        text.frame = NSRect(x: 0, y: 0, width: 388, height: 150)
        scroll.documentView = text; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
    }
    @objc private func toggleOriginal() { originalScroll.isHidden = compare.state != .on; resize() }
    @objc private func replaceClicked() { onReplace?() }
    @objc private func copyClicked() { onCopy?() }
    @objc private func cancelClicked() { onCancel?() }
}
