import AppKit
import Foundation

@MainActor
private final class ProfileNameInputController: NSObject, NSTextFieldDelegate {
    private let nameField: NSTextField
    private let errorLabel: NSTextField
    private let saveButton: NSButton
    private let existingComparableNames: Set<String>

    init(nameField: NSTextField,
         errorLabel: NSTextField,
         saveButton: NSButton,
         existingProfiles: [String]) {
        self.nameField = nameField
        self.errorLabel = errorLabel
        self.saveButton = saveButton
        self.existingComparableNames = Set(existingProfiles.map(Self.comparableName))
    }

    func controlTextDidChange(_ obj: Notification) {
        updateValidationState()
    }

    func currentName() -> String {
        nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isDuplicateName() -> Bool {
        existingComparableNames.contains(Self.comparableName(currentName()))
    }

    func updateValidationState() {
        let duplicate = isDuplicateName()
        errorLabel.isHidden = !duplicate
        saveButton.isEnabled = !duplicate
    }

    private static func comparableName(_ raw: String) -> String {
        let collapsed = raw
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.lowercased()
    }
}

struct CodexAgentSettingsSelection {
    let projectHome: String?
    let allowedRepos: [String]
}

@MainActor
final class CodexAgentSettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private let projectHomeLabel = NSTextField(labelWithString: "<tmp and delete after>")
    private let statusLabel = NSTextField(labelWithString: "Loading writable GitHub repos...")
    private let progressIndicator = NSProgressIndicator()
    private let chooseButton = NSButton(title: "Choose Folder…", target: nil, action: nil)
    private let clearButton = NSButton(title: "Clear", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let reposHint = NSTextField(labelWithString: "Leave all unchecked to allow every available repo.")

    private let onSave: (CodexAgentSettingsSelection) -> Void
    private let onClose: () -> Void

    private var repos: [String] = []
    private var selectedRepos: Set<String> = []
    private(set) var projectHome: String?
    private var configLoaded = false
    private var reposLoaded = false
    private var loadCompleted = false

    init(onSave: @escaping (CodexAgentSettingsSelection) -> Void, onClose: @escaping () -> Void) {
        self.onSave = onSave
        self.onClose = onClose

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Agents Settings"
        panel.isFloatingPanel = true
        panel.center()
        panel.setFrameAutosaveName("CodexAgentSettingsPanel")
        super.init(window: panel)
        panel.delegate = self

        buildUI(in: panel)
        setLoading()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func setLoading() {
        configLoaded = false
        reposLoaded = false
        loadCompleted = false
        saveButton.isEnabled = false
        chooseButton.isEnabled = false
        clearButton.isEnabled = false
        statusLabel.isHidden = false
        statusLabel.stringValue = "Loading writable GitHub repos..."
        progressIndicator.startAnimation(nil)
        tableView.reloadData()
    }

    func applyCurrentConfig(_ currentConfig: CodexCoreCLIClient.AgentsConfig) {
        configLoaded = true
        projectHome = currentConfig.projectHome
        updateProjectHomeLabel()
        selectedRepos = Set(currentConfig.allowedRepos)
        chooseButton.isEnabled = true
        clearButton.isEnabled = true
    }

    func applyAvailableRepos(_ availableRepos: [CodexCoreCLIClient.AvailableRepo]) {
        reposLoaded = true
        repos = availableRepos.map(\.fullName)
        loadCompleted = true
        saveButton.isEnabled = configLoaded
        progressIndicator.stopAnimation(nil)
        statusLabel.isHidden = true
        tableView.reloadData()
    }

    func applyLoadError(_ message: String) {
        loadCompleted = false
        repos = []
        saveButton.isEnabled = false
        progressIndicator.stopAnimation(nil)
        statusLabel.isHidden = false
        statusLabel.stringValue = message
        tableView.reloadData()
    }

    @objc func chooseProjectHome(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let projectHome {
            panel.directoryURL = URL(fileURLWithPath: projectHome)
        }
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        projectHome = url.path
        updateProjectHomeLabel()
    }

    @objc func clearProjectHome(_ sender: Any?) {
        projectHome = nil
        updateProjectHomeLabel()
    }

    @objc func save(_ sender: Any?) {
        guard loadCompleted else {
            return
        }
        onSave(CodexAgentSettingsSelection(projectHome: projectHome, allowedRepos: selectedRepos.sorted()))
        close()
    }

    @objc func cancel(_ sender: Any?) {
        close()
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        if !reposLoaded {
            return 0
        }
        return max(repos.count, 1)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if repos.isEmpty {
            let label = NSTextField(labelWithString: "No writable GitHub repos available.")
            label.textColor = .secondaryLabelColor
            return label
        }

        let repo = repos[row]
        let identifier = NSUserInterfaceItemIdentifier("repo-cell")
        let cellView = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? makeRepoCellView(identifier: identifier)
        guard let button = cellView.subviews.compactMap({ $0 as? NSButton }).first else {
            return cellView
        }
        button.target = self
        button.action = #selector(toggleRepoSelection(_:))
        button.state = selectedRepos.contains(repo) ? .on : .off
        button.identifier = NSUserInterfaceItemIdentifier(rawValue: repo)
        button.title = repo
        return cellView
    }

    @objc private func toggleRepoSelection(_ sender: NSButton) {
        guard let repo = sender.identifier?.rawValue else {
            return
        }
        if sender.state == .on {
            selectedRepos.insert(repo)
        } else {
            selectedRepos.remove(repo)
        }
    }

    private func buildUI(in panel: NSPanel) {
        guard let contentView = panel.contentView else {
            return
        }

        let projectHomeTitle = NSTextField(labelWithString: "Home Project Folder")
        projectHomeTitle.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        projectHomeTitle.frame = NSRect(x: 20, y: 510, width: 460, height: 20)
        contentView.addSubview(projectHomeTitle)

        projectHomeLabel.lineBreakMode = .byTruncatingMiddle
        projectHomeLabel.frame = NSRect(x: 20, y: 484, width: 460, height: 20)
        contentView.addSubview(projectHomeLabel)

        chooseButton.target = self
        chooseButton.action = #selector(chooseProjectHome(_:))
        chooseButton.frame = NSRect(x: 20, y: 448, width: 140, height: 28)
        contentView.addSubview(chooseButton)

        clearButton.target = self
        clearButton.action = #selector(clearProjectHome(_:))
        clearButton.frame = NSRect(x: 170, y: 448, width: 80, height: 28)
        contentView.addSubview(clearButton)

        let reposTitle = NSTextField(labelWithString: "Allowed Review Repos")
        reposTitle.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        reposTitle.frame = NSRect(x: 20, y: 410, width: 460, height: 20)
        contentView.addSubview(reposTitle)

        reposHint.textColor = .secondaryLabelColor
        reposHint.frame = NSRect(x: 20, y: 388, width: 460, height: 18)
        contentView.addSubview(reposHint)

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.frame = NSRect(x: 20, y: 360, width: 16, height: 16)
        contentView.addSubview(progressIndicator)

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 44, y: 358, width: 436, height: 18)
        contentView.addSubview(statusLabel)

        scrollView.frame = NSRect(x: 20, y: 80, width: 460, height: 270)
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("repo"))
        column.width = 440
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .none
        tableView.focusRingType = .none
        tableView.delegate = self
        tableView.dataSource = self
        scrollView.documentView = tableView
        contentView.addSubview(scrollView)

        cancelButton.target = self
        cancelButton.action = #selector(cancel(_:))
        cancelButton.frame = NSRect(x: 300, y: 24, width: 80, height: 30)
        contentView.addSubview(cancelButton)

        saveButton.target = self
        saveButton.action = #selector(save(_:))
        saveButton.frame = NSRect(x: 392, y: 24, width: 88, height: 30)
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)
    }

    private func updateProjectHomeLabel() {
        projectHomeLabel.stringValue = projectHome ?? "<tmp and delete after>"
    }

    private func makeRepoCellView(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cellView = NSTableCellView(frame: NSRect(x: 0, y: 0, width: 440, height: 24))
        cellView.identifier = identifier

        let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleRepoSelection(_:)))
        button.frame = NSRect(x: 4, y: 1, width: 432, height: 22)
        button.setButtonType(.switch)
        cellView.addSubview(button)
        return cellView
    }
}

extension AppDelegate {
    func promptForProfileName(existingProfiles: [String]) -> String? {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Add Profile"
        alert.informativeText = "This auth will be linked to this profile."

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 76))
        let nameField = NSTextField(frame: NSRect(x: 0, y: 34, width: 320, height: 24))
        accessory.addSubview(nameField)

        let errorLabel = NSTextField(labelWithString: "Profile already exists.")
        errorLabel.frame = NSRect(x: 0, y: 10, width: 320, height: 16)
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true
        accessory.addSubview(errorLabel)

        alert.accessoryView = accessory

        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        guard let saveButton = alert.buttons.first else {
            return nil
        }

        let inputController = ProfileNameInputController(nameField: nameField,
                                                         errorLabel: errorLabel,
                                                         saveButton: saveButton,
                                                         existingProfiles: existingProfiles)
        nameField.delegate = inputController
        inputController.updateValidationState()

        DispatchQueue.main.async {
            nameField.window?.makeFirstResponder(nameField)
        }

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return nil
        }

        let name = inputController.currentName()
        guard !name.isEmpty else {
            showError(CodexAuthCLIClient.Error(message: "Profile name cannot be empty."))
            return nil
        }
        guard !inputController.isDuplicateName() else {
            return nil
        }

        return name
    }
}
