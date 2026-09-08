import AppKit

@MainActor
private final class StatusDot: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class MenuBarStatus: NSObject {
    var onRewrite: (() -> Void)?
    var onCancel: (() -> Void)?
    var onProvider: ((RewriteProvider) -> Void)?
    private var providerItems: [NSMenuItem] = []
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let progress = NSMenuItem(title: "Rewriting…", action: nil, keyEquivalent: "")
    private let rewrite = NSMenuItem(title: "Rewrite", action: #selector(begin), keyEquivalent: "r")
    private let cancel = NSMenuItem(title: "Cancel Rewrite", action: #selector(cancelRewrite), keyEquivalent: "")
    private let errorDetails = NSMenuItem()
    private let statusDivider = NSMenuItem.separator()
    private var errorMessage: String?
    private let dot = StatusDot(frame: .zero)
    private var isRewriting = false

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
        for entry in [errorDetails, progress, cancel] { entry.target = self; menu.addItem(entry) }
        menu.addItem(statusDivider)
        menu.addItem(rewrite)
        menu.addItem(.separator())
        progress.isEnabled = false
        rewrite.target = self; rewrite.keyEquivalentModifierMask = .option
        let providers = NSMenu(); providers.autoenablesItems = false
        for provider in RewriteProvider.allCases {
            let entry = providers.addItem(withTitle: provider.rawValue, action: #selector(providerClicked(_:)), keyEquivalent: "")
            entry.target = self; providerItems.append(entry)
        }
        let provider = NSMenuItem(title: "Provider", action: nil, keyEquivalent: "")
        provider.submenu = providers; menu.addItem(provider)
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "").target = self
        item.menu = menu; setRewriting(false)
    }
    func setRewriting(_ active: Bool) {
        isRewriting = active; errorMessage = nil; errorDetails.isHidden = true
        statusDivider.isHidden = !active
        dot.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        dot.isHidden = !active; progress.isHidden = !active; cancel.isHidden = !active
        rewrite.isEnabled = !active
        updateTooltip()
    }
    func showError(_ message: String, opensPermissions: Bool = false) {
        setRewriting(false); errorMessage = message
        statusDivider.isHidden = false
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
        let label = errorMessage.map { "Rewrite: \($0)" } ?? (isRewriting ? "Rewriting…" : "Rewrite · ⌥R")
        item.button?.toolTip = label; item.button?.setAccessibilityLabel(label)
    }
    @objc private func openPermissions() { Accessibility.openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func begin() { onRewrite?() }
    @objc private func cancelRewrite() { onCancel?() }
    func setProvider(_ provider: RewriteProvider) {
        for entry in providerItems { entry.state = entry.title == provider.rawValue ? .on : .off }
    }
    @objc private func providerClicked(_ sender: NSMenuItem) {
        guard let provider = RewriteProvider(rawValue: sender.title) else { return }
        onProvider?(provider); setProvider(provider)
    }
}
