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
private final class CodexAgentSettingsDialogController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let projectHomeLabel: NSTextField
    private let repos: [String]
    private var selectedRepos: Set<String>
    private(set) var projectHome: String?

    init(
        projectHomeLabel: NSTextField,
        initialProjectHome: String?,
        repos: [String],
        selectedRepos: Set<String>
    ) {
        self.projectHomeLabel = projectHomeLabel
        self.projectHome = initialProjectHome
        self.repos = repos
        self.selectedRepos = selectedRepos
        super.init()
        updateProjectHomeLabel()
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

    func selection() -> CodexAgentSettingsSelection {
        CodexAgentSettingsSelection(
            projectHome: projectHome,
            allowedRepos: selectedRepos.sorted()
        )
    }

    private func updateProjectHomeLabel() {
        projectHomeLabel.stringValue = projectHome ?? "<tmp and delete after>"
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        max(repos.count, 1)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if repos.isEmpty {
            let label = NSTextField(labelWithString: "No GitHub repos available.")
            label.textColor = .secondaryLabelColor
            return label
        }

        let repo = repos[row]
        let button = NSButton(checkboxWithTitle: repo, target: self, action: #selector(toggleRepoSelection(_:)))
        button.state = selectedRepos.contains(repo) ? .on : .off
        button.identifier = NSUserInterfaceItemIdentifier(rawValue: repo)
        return button
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

    func promptForCodexAgentSettings(
        currentConfig: CodexCoreCLIClient.AgentsConfig,
        availableRepos: [CodexCoreCLIClient.AvailableRepo]
    ) -> CodexAgentSettingsSelection? {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Agents Settings"
        alert.informativeText = "Configure the review project folder and repo filters."

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 420))

        let projectHomeTitle = NSTextField(labelWithString: "Home Project Folder")
        projectHomeTitle.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        projectHomeTitle.frame = NSRect(x: 0, y: 392, width: 420, height: 20)
        accessory.addSubview(projectHomeTitle)

        let projectHomeLabel = NSTextField(labelWithString: "")
        projectHomeLabel.lineBreakMode = .byTruncatingMiddle
        projectHomeLabel.frame = NSRect(x: 0, y: 364, width: 420, height: 20)
        accessory.addSubview(projectHomeLabel)

        let chooseButton = NSButton(title: "Choose Folder…", target: nil, action: nil)
        chooseButton.frame = NSRect(x: 0, y: 332, width: 140, height: 28)
        accessory.addSubview(chooseButton)

        let clearButton = NSButton(title: "Clear", target: nil, action: nil)
        clearButton.frame = NSRect(x: 150, y: 332, width: 80, height: 28)
        accessory.addSubview(clearButton)

        let reposTitle = NSTextField(labelWithString: "Allowed Review Repos")
        reposTitle.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        reposTitle.frame = NSRect(x: 0, y: 300, width: 420, height: 20)
        accessory.addSubview(reposTitle)

        let reposHint = NSTextField(labelWithString: "Leave all unchecked to allow every available repo.")
        reposHint.textColor = .secondaryLabelColor
        reposHint.frame = NSRect(x: 0, y: 276, width: 420, height: 18)
        accessory.addSubview(reposHint)

        let repoNames = availableRepos.map(\.fullName)
        let selectedRepos = Set(currentConfig.allowedRepos)
        let controller = CodexAgentSettingsDialogController(
            projectHomeLabel: projectHomeLabel,
            initialProjectHome: currentConfig.projectHome,
            repos: repoNames,
            selectedRepos: selectedRepos
        )

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 264))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let tableView = NSTableView(frame: scrollView.bounds)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("repo"))
        column.width = 400
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .none
        tableView.delegate = controller
        tableView.dataSource = controller
        scrollView.documentView = tableView
        accessory.addSubview(scrollView)
        chooseButton.target = controller
        chooseButton.action = #selector(CodexAgentSettingsDialogController.chooseProjectHome(_:))
        clearButton.target = controller
        clearButton.action = #selector(CodexAgentSettingsDialogController.clearProjectHome(_:))

        alert.accessoryView = accessory
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        return controller.selection()
    }
}
