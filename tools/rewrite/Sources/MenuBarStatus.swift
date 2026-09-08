import AppKit

@MainActor
private final class StatusDot: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class MenuBarStatus: NSObject, NSMenuDelegate {
    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?
    var onChoose: ((EditAction) -> Void)?
    private var actionItems: [NSMenuItem] = []
    var onCancel: (() -> Void)?
    var onProvider: ((RewriteProvider) -> Void)?
    private var providerItems: [NSMenuItem] = []
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let progress = NSMenuItem(title: "Rewriting…", action: nil, keyEquivalent: "")
    private let rewrite = NSMenuItem(title: "Rewrite", action: nil, keyEquivalent: "r")
    private let cancel = NSMenuItem(title: "Cancel Rewrite", action: #selector(cancelRewrite), keyEquivalent: "")
    private let errorDetails = NSMenuItem()
    private var errorMessage: String?
    private let dot = StatusDot(frame: .zero)
    private var action: EditAction?

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
        let menu = NSMenu(); menu.autoenablesItems = false; menu.delegate = self
        for entry in [progress, errorDetails, cancel, rewrite] { entry.target = self; menu.addItem(entry) }
        progress.isEnabled = false
        rewrite.isEnabled = false; rewrite.keyEquivalentModifierMask = .option
        for (index, action) in EditAction.allCases.enumerated() {
            let entry = menu.addItem(withTitle: action.rawValue, action: #selector(choose(_:)), keyEquivalent: String(index + 1))
            entry.keyEquivalentModifierMask = .option; entry.target = self; entry.tag = index
            actionItems.append(entry)
        }
        menu.addItem(.separator())
        let providers = NSMenu(); providers.autoenablesItems = false
        for provider in RewriteProvider.allCases {
            let entry = providers.addItem(withTitle: provider.rawValue, action: #selector(providerClicked(_:)), keyEquivalent: "")
            entry.target = self; providerItems.append(entry)
        }
        let provider = NSMenuItem(title: "Provider", action: nil, keyEquivalent: "")
        provider.submenu = providers; menu.addItem(provider)
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "").target = self
        item.menu = menu; setRewriting(nil)
    }
    func setRewriting(_ action: EditAction?) {
        self.action = action; errorMessage = nil; errorDetails.isHidden = true
        dot.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        dot.isHidden = action == nil; progress.isHidden = action == nil; cancel.isHidden = action == nil
        setActionsEnabled(action == nil)
        progress.title = action.map { "Rewriting… · \($0.rawValue)" } ?? "Rewriting…"
        updateTooltip()
    }
    func showError(_ message: String, opensPermissions: Bool = false) {
        setRewriting(nil); errorMessage = message
        progress.title = "Rewrite needs attention"; progress.isHidden = false
        errorDetails.view = nil
        errorDetails.action = opensPermissions ? #selector(openPermissions) : nil
        errorDetails.title = opensPermissions ? "Allow Rewrite in System Settings…" : ""
        if !opensPermissions {
            let label = NSTextField(wrappingLabelWithString: message)
            label.font = .systemFont(ofSize: 12); label.preferredMaxLayoutWidth = 280
            label.frame = NSRect(x: 14, y: 8, width: 280, height: label.fittingSize.height)
            let view = NSView(frame: NSRect(x: 0, y: 0, width: 308, height: label.frame.height + 16))
            view.addSubview(label); errorDetails.view = view
        }
        errorDetails.isHidden = false
        dot.isHidden = false; dot.layer?.backgroundColor = NSColor.systemOrange.cgColor
        updateTooltip()
    }
    func remove() { NSStatusBar.system.removeStatusItem(item) }
    private func updateTooltip() {
        let label = errorMessage.map { "Rewrite: \($0)" } ?? action.map { "Rewriting… · \($0.rawValue)" } ?? "Rewrite · ⌥R"
        item.button?.toolTip = label; item.button?.setAccessibilityLabel(label)
    }
    @objc private func openPermissions() { Accessibility.openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
    func open() { item.button?.performClick(nil) }
    func menuWillOpen(_ menu: NSMenu) { onOpen?() }
    func menuDidClose(_ menu: NSMenu) { onClose?() }
    func setActionsEnabled(_ enabled: Bool) {
        for entry in actionItems { entry.isEnabled = enabled }
    }
    @objc private func choose(_ sender: NSMenuItem) { onChoose?(EditAction.allCases[sender.tag]) }
    @objc private func cancelRewrite() { onCancel?() }
    func setProvider(_ provider: RewriteProvider) {
        for entry in providerItems { entry.state = entry.title == provider.rawValue ? .on : .off }
    }
    @objc private func providerClicked(_ sender: NSMenuItem) {
        guard let provider = RewriteProvider(rawValue: sender.title) else { return }
        onProvider?(provider); setProvider(provider)
    }
}
