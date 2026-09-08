import AppKit

@MainActor
final class Settings: NSObject {
    var onSave: (() -> Void)?
    private let defaults: UserDefaults
    private let window: NSWindow
    private let provider = NSPopUpButton()
    private let model = NSTextField(labelWithString: "")
    private let notice = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let save = NSButton(title: "Done", target: nil, action: nil)

    var configuration: RewriteConfiguration {
        let kind = RewriteProvider.saved(defaults.string(forKey: "processor")) ?? .openai
        return RewriteConfiguration(kind: kind)
    }
    var isConfigured: Bool { RewriteProvider.saved(defaults.string(forKey: "processor")) != nil }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 280), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Rewrite Settings"; window.isReleasedWhenClosed = false
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20); stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor)])
        provider.addItems(withTitles: RewriteProvider.allCases.map(\.rawValue)); provider.target = self; provider.action = #selector(providerChanged)
        provider.setAccessibilityLabel("Provider")
        model.setAccessibilityLabel("Model")
        for view in [NSTextField(labelWithString: "Provider"), provider, notice, NSTextField(labelWithString: "Model"), model, status] { stack.addArrangedSubview(view) }
        for field in [notice, status] { field.font = .systemFont(ofSize: 11); field.textColor = .secondaryLabelColor; field.widthAnchor.constraint(equalToConstant: 400).isActive = true }
        save.bezelStyle = .rounded; save.keyEquivalent = "\r"; save.target = self; save.action = #selector(saveSettings)
        let permission = NSButton(title: "Accessibility…", target: self, action: #selector(openPermissions)); permission.bezelStyle = .rounded
        let row = NSStackView(views: [permission, save]); row.spacing = 190; stack.addArrangedSubview(row)
    }
    func show() {
        provider.selectItem(withTitle: configuration.kind.rawValue); model.stringValue = configuration.kind.modelLabel
        notice.stringValue = configuration.kind.notice
        window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        status.stringValue = "Sign in through Pi using /login. Rewrite checks your sign-in automatically."
    }
    @objc private func providerChanged() {
        let kind = selectedKind
        model.stringValue = kind.modelLabel; notice.stringValue = kind.notice
    }
    private var selectedKind: RewriteProvider { RewriteProvider(rawValue: provider.titleOfSelectedItem ?? "") ?? .openai }
    @objc private func saveSettings() {
        defaults.set(selectedKind.rawValue, forKey: "processor")
        defaults.removeObject(forKey: "model")
        window.orderOut(nil); onSave?()
    }
    @objc private func openPermissions() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
