import AppKit

/// Only shown when a request fails or its result cannot be applied safely.
@MainActor
final class ResultNotice: NSObject, NSWindowDelegate {
    var onCopy: (() -> Void)?
    var onClose: (() -> Void)?
    let panel: NSPanel
    private let note = NSTextField(wrappingLabelWithString: "")
    private let result = NSTextView()
    private let scroll = NSScrollView()
    private let copy = NSButton(title: "Copy", target: nil, action: nil)
    private let close = NSButton(title: "Close", target: nil, action: nil)

    override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 140), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        super.init()
        panel.title = "Rewrite"; panel.level = .floating; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false; panel.delegate = self
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false; panel.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: panel.contentView!.topAnchor, constant: 16)])
        note.widthAnchor.constraint(equalToConstant: 388).isActive = true; stack.addArrangedSubview(note)
        result.isEditable = false; result.isSelectable = true; result.isRichText = false
        result.font = .systemFont(ofSize: 13); result.textContainerInset = NSSize(width: 4, height: 6)
        result.autoresizingMask = [.width]; result.textContainer?.widthTracksTextView = true
        result.frame = NSRect(x: 0, y: 0, width: 388, height: 140); result.setAccessibilityLabel("Rewritten text")
        scroll.documentView = result; scroll.hasVerticalScroller = true
        scroll.widthAnchor.constraint(equalToConstant: 388).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 140).isActive = true; stack.addArrangedSubview(scroll)
        for (button, selector) in [(close, #selector(closeClicked)), (copy, #selector(copyClicked))] {
            button.bezelStyle = .roundRect; button.controlSize = .small; button.target = self; button.action = selector
        }
        close.keyEquivalent = "\u{1b}"; copy.keyEquivalent = "c"; copy.keyEquivalentModifierMask = [.command, .shift]
        stack.addArrangedSubview(NSStackView(views: [close, copy]))
    }
    func show(_ message: String, result text: String? = nil, at point: NSPoint = NSEvent.mouseLocation) {
        note.stringValue = message; result.string = text ?? ""
        scroll.isHidden = text == nil; copy.isHidden = text == nil
        panel.contentView?.layoutSubtreeIfNeeded()
        let textHeight = note.fittingSize.height
        panel.setContentSize(NSSize(width: 420, height: 76 + textHeight + (text == nil ? 0 : 152)))
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main!
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        panel.setFrameTopLeftPoint(NSPoint(x: min(max(point.x, visible.minX), visible.maxX - panel.frame.width),
            y: max(min(point.y, visible.maxY), visible.minY + panel.frame.height)))
        NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(text == nil ? close : copy)
    }
    func closePanel() { panel.orderOut(nil); result.string = ""; note.stringValue = "" }
    func windowShouldClose(_ sender: NSWindow) -> Bool { onClose?(); return false }
    @objc private func closeClicked() { onClose?() }
    @objc private func copyClicked() { onCopy?() }
}
