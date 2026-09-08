import AppKit

@MainActor
private final class StatusDot: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class MenuBarStatus: NSObject {
    var onRewrite: (() -> Void)?
    var onCancel: (() -> Void)?
    var onSettings: (() -> Void)?
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let progress = NSMenuItem(title: "Rewriting…", action: nil, keyEquivalent: "")
    private let rewrite = NSMenuItem(title: "Rewrite Selection", action: #selector(begin), keyEquivalent: "")
    private let cancel = NSMenuItem(title: "Cancel Rewrite", action: #selector(cancelRewrite), keyEquivalent: "")
    private let errorDetails = NSMenuItem()
    private var errorMessage: String?
    private let dot = StatusDot(frame: .zero)
    private var action: EditAction?
    var shortcutLabel = "⌥R" { didSet { updateTooltip() } }

    override init() {
        super.init()
        item.button?.image = NSImage(systemSymbolName: "pencil.line", accessibilityDescription: "Rewrite")
        if let button = item.button {
            dot.frame = NSRect(x: button.bounds.maxX - 6, y: button.isFlipped ? button.bounds.minY + 1 : button.bounds.maxY - 6, width: 5, height: 5)
            dot.autoresizingMask = [.minXMargin, button.isFlipped ? .maxYMargin : .minYMargin]
            dot.wantsLayer = true; dot.layer?.cornerRadius = 2.5
            dot.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            dot.setAccessibilityElement(false); button.addSubview(dot)
        }
        let menu = NSMenu(); menu.autoenablesItems = false
        for entry in [progress, errorDetails, cancel, rewrite] { entry.target = self; menu.addItem(entry) }
        progress.isEnabled = false
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(settingsClicked), keyEquivalent: ",")
        settings.target = self; menu.addItem(settings)
        menu.addItem(withTitle: "Quit Rewrite", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu; setRewriting(nil)
    }
    func setRewriting(_ action: EditAction?) {
        self.action = action; errorMessage = nil; errorDetails.isHidden = true
        dot.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        dot.isHidden = action == nil; progress.isHidden = action == nil; cancel.isHidden = action == nil
        rewrite.isEnabled = action == nil
        progress.title = action.map { "Rewriting… · \($0.rawValue)" } ?? "Rewriting…"
        updateTooltip()
    }
    func showError(_ message: String) {
        setRewriting(nil); errorMessage = message
        progress.title = "Rewrite needs attention"; progress.isHidden = false
        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 12); label.preferredMaxLayoutWidth = 280
        label.frame = NSRect(x: 14, y: 8, width: 280, height: label.fittingSize.height)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 308, height: label.frame.height + 16))
        view.addSubview(label); errorDetails.view = view; errorDetails.isHidden = false
        dot.isHidden = false; dot.layer?.backgroundColor = NSColor.systemOrange.cgColor
        updateTooltip()
    }
    func remove() { NSStatusBar.system.removeStatusItem(item) }
    private func updateTooltip() {
        let label = errorMessage.map { "Rewrite: \($0)" } ?? action.map { "Rewriting… · \($0.rawValue)" } ?? "Rewrite · \(shortcutLabel)"
        item.button?.toolTip = label; item.button?.setAccessibilityLabel(label)
    }
    @objc private func begin() { onRewrite?() }
    @objc private func cancelRewrite() { onCancel?() }
    @objc private func settingsClicked() { onSettings?() }
}
