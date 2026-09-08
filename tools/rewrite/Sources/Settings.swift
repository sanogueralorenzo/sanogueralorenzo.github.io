import AppKit

@MainActor
final class Settings: NSObject {
    var onShortcut: ((Shortcut) -> Bool)?
    var onSave: (() -> Void)?
    private let defaults: UserDefaults
    private let window: NSWindow
    private let provider = NSPopUpButton()
    private let model = NSComboBox()
    private let notice = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let recorder = ShortcutRecorder()
    private let service = ProcessorService()
    private var refreshTask: Task<Void, Never>?
    private let save = NSButton(title: "Done", target: nil, action: nil)

    var configuration: ProcessorConfiguration {
        let kind = ProcessorKind.saved(defaults.string(forKey: "processor")) ?? .openai
        return ProcessorConfiguration(kind: kind, model: kind.modelID(isConfigured ? defaults.string(forKey: "model") ?? "" : ""))
    }
    var isConfigured: Bool { ProcessorKind.saved(defaults.string(forKey: "processor")) != nil }
    var shortcut: Shortcut {
        guard let data = defaults.data(forKey: "shortcut"), let value = try? JSONDecoder().decode(Shortcut.self, from: data) else { return .standard }
        return value.migratingLegacyShortcut
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 340), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Rewrite Settings"; window.isReleasedWhenClosed = false
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20); stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor)])
        provider.addItems(withTitles: ProcessorKind.allCases.map(\.rawValue)); provider.target = self; provider.action = #selector(providerChanged)
        provider.setAccessibilityLabel("Provider")
        model.usesDataSource = false; model.completes = true; model.placeholderString = "Model name"; model.setAccessibilityLabel("Model")
        let refresh = NSButton(title: "Refresh", target: self, action: #selector(refreshModels)); refresh.bezelStyle = .rounded
        let modelRow = NSStackView(views: [model, refresh]); model.widthAnchor.constraint(equalToConstant: 260).isActive = true
        recorder.bezelStyle = .rounded; recorder.title = shortcut.label; recorder.shortcut = shortcut
        recorder.setAccessibilityLabel("Record global shortcut")
        recorder.target = self; recorder.action = #selector(recordShortcut)
        recorder.onRecord = { [weak self] value in
            guard let self, self.onShortcut?(value) == true else { return false }
            self.defaults.set(try? JSONEncoder().encode(value), forKey: "shortcut"); return true
        }
        let shortcutRow = NSStackView(views: [NSTextField(labelWithString: "Shortcut"), recorder]); shortcutRow.spacing = 16
        for view in [NSTextField(labelWithString: "Provider"), provider, notice, NSTextField(labelWithString: "Model"), modelRow, shortcutRow, status] { stack.addArrangedSubview(view) }
        for field in [notice, status] { field.font = .systemFont(ofSize: 11); field.textColor = .secondaryLabelColor; field.widthAnchor.constraint(equalToConstant: 400).isActive = true }
        save.bezelStyle = .rounded; save.keyEquivalent = "\r"; save.target = self; save.action = #selector(saveSettings)
        let permission = NSButton(title: "Accessibility…", target: self, action: #selector(openPermissions)); permission.bezelStyle = .rounded
        let row = NSStackView(views: [permission, save]); row.spacing = 190; stack.addArrangedSubview(row)
    }
    func show() {
        provider.selectItem(withTitle: configuration.kind.rawValue); model.stringValue = configuration.kind.modelLabel(configuration.resolvedModel)
        notice.stringValue = configuration.kind.notice
        window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        refreshModels()
    }
    @objc private func providerChanged() {
        let kind = selectedKind
        model.stringValue = kind.modelLabel(kind.preferredModel); notice.stringValue = kind.notice
        refreshModels()
    }
    private var selectedKind: ProcessorKind { ProcessorKind(rawValue: provider.titleOfSelectedItem ?? "") ?? .openai }
    @objc private func refreshModels() {
        refreshTask?.cancel(); service.cancel()
        let kind = selectedKind
        status.stringValue = "Checking Pi sign-in and models…"; save.isEnabled = false
        refreshTask = Task { @MainActor in
            do {
                let models = try await service.models(for: kind)
                try Task.checkCancellation()
                model.removeAllItems(); model.addItems(withObjectValues: models.map { kind.modelLabel($0) })
                if model.stringValue.isEmpty, let first = models.first { model.stringValue = kind.modelLabel(first) }
                status.stringValue = "Pi is ready. Choose a model or enter its ID."
                save.isEnabled = !models.isEmpty
            } catch { if !Task.isCancelled { status.stringValue = error.localizedDescription; save.isEnabled = false } }
        }
    }
    @objc private func saveSettings() {
        let value = model.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count < 160, !value.contains("\n") else { status.stringValue = "Enter a model name."; return }
        do { _ = try ProcessorService.arguments(ProcessorConfiguration(kind: selectedKind, model: selectedKind.modelID(value))) }
        catch { status.stringValue = error.localizedDescription; return }
        defaults.set(selectedKind.rawValue, forKey: "processor"); defaults.set(selectedKind.modelID(value), forKey: "model")
        window.orderOut(nil); onSave?()
    }
    @objc private func recordShortcut() { recorder.record() }
    @objc private func openPermissions() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
