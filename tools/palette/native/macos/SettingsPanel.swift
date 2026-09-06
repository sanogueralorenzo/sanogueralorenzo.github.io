import AppKit

@MainActor
final class SettingsPanel: NSPanel {
    var onSave: ((ClipboardPolicy) -> Void)?
    var onClear: (() -> Void)?
    private var policy: ClipboardPolicy
    private let retention = NSPopUpButton()
    private let excluded = NSPopUpButton()
    private let remove = NSButton(title: "Remove", target: nil, action: nil)

    init(policy: ClipboardPolicy, count: Int) {
        self.policy = policy
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 260), styleMask: [.titled], backing: .buffered, defer: false)
        title = "Settings"
        appearance = NSAppearance(named: .darkAqua)
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: contentView!.topAnchor, constant: 22)])
        for (name, days) in [("7 days", 7.0), ("30 days", 30.0), ("90 days", 90.0), ("Until deleted", -1.0)] { retention.addItem(withTitle: name); retention.lastItem?.representedObject = days }
        if let days = policy.retentionDays, ![7.0, 30, 90].contains(days) { retention.addItem(withTitle: "\(Int(days)) days"); retention.lastItem?.representedObject = days }
        retention.select(retention.itemArray.first { $0.representedObject as? Double == (policy.retentionDays ?? -1) })
        retention.setAccessibilityLabel("Keep history")
        stack.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: "Keep history"), retention]))
        let note = NSTextField(wrappingLabelWithString: "Pinned clips stay until deleted.")
        note.font = .systemFont(ofSize: 12); note.textColor = .secondaryLabelColor
        stack.addArrangedSubview(note); note.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let label = NSTextField(labelWithString: "Don’t save copies from")
        label.font = .systemFont(ofSize: 13, weight: .medium); stack.addArrangedSubview(label)
        excluded.setAccessibilityLabel("Excluded apps")
        excluded.widthAnchor.constraint(equalToConstant: 140).isActive = true
        let add = NSButton(title: "Add app…", target: self, action: #selector(addApp))
        remove.target = self; remove.action = #selector(removeApp)
        stack.addArrangedSubview(NSStackView(views: [excluded, add, remove]))
        updateApps()
        let clear = NSButton(title: "Clear unpinned…", target: self, action: #selector(clearHistory))
        clear.isEnabled = count > 0
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelSettings)); cancel.keyEquivalent = "\u{1b}"
        let done = NSButton(title: "Save", target: self, action: #selector(save)); done.keyEquivalent = "\r"
        let actions = NSStackView(views: [clear, NSView(), cancel, done]); actions.spacing = 8
        stack.addArrangedSubview(actions); actions.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func updateApps() {
        excluded.removeAllItems()
        for id in policy.excludedAppIds {
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            let name = url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? id
            excluded.addItem(withTitle: name); excluded.lastItem?.representedObject = id
        }
        if policy.excludedAppIds.isEmpty { excluded.addItem(withTitle: "None") }
        remove.isEnabled = !policy.excludedAppIds.isEmpty
    }
    @objc private func addApp() {
        let picker = NSOpenPanel()
        picker.title = "Choose an app to exclude"; picker.prompt = "Exclude app"
        picker.directoryURL = URL(fileURLWithPath: "/Applications")
        picker.allowedContentTypes = [.applicationBundle]
        picker.beginSheetModal(for: self) { [weak self] result in
            guard result == .OK, let url = picker.url, let id = Bundle(url: url)?.bundleIdentifier, let self else { return }
            if !self.policy.excludedAppIds.contains(id) { self.policy.excludedAppIds.append(id) }
            self.updateApps()
        }
    }
    @objc private func removeApp() {
        guard let id = excluded.selectedItem?.representedObject as? String else { return }
        policy.excludedAppIds.removeAll { $0 == id }; updateApps()
    }
    @objc private func clearHistory() {
        let alert = NSAlert(); alert.messageText = "Clear unpinned history?"
        alert.informativeText = "Pinned clips will stay. This cannot be undone."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Clear history")
        alert.beginSheetModal(for: self) { [weak self] response in if response == .alertSecondButtonReturn { self?.onClear?() } }
    }
    @objc private func save() {
        let days = retention.selectedItem?.representedObject as? Double ?? 30
        policy.retentionDays = days < 0 ? nil : days
        policy.ignoreSensitive = true
        onSave?(policy); sheetParent?.endSheet(self)
    }
    @objc private func cancelSettings() { sheetParent?.endSheet(self) }
}
