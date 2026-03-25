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
private final class CodexAgentSettingsDialogController: NSObject {
    private let projectHomeLabel: NSTextField
    private let repoButtons: [(repo: String, button: NSButton)]
    private(set) var projectHome: String?

    init(
        projectHomeLabel: NSTextField,
        initialProjectHome: String?,
        repoButtons: [(repo: String, button: NSButton)]
    ) {
        self.projectHomeLabel = projectHomeLabel
        self.projectHome = initialProjectHome
        self.repoButtons = repoButtons
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
        let allowedRepos = repoButtons
            .filter { $0.button.state == .on }
            .map(\.repo)
            .sorted()
        return CodexAgentSettingsSelection(projectHome: projectHome, allowedRepos: allowedRepos)
    }

    private func updateProjectHomeLabel() {
        projectHomeLabel.stringValue = projectHome ?? "<tmp and delete after>"
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

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 264))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let repoStack = NSStackView()
        repoStack.orientation = .vertical
        repoStack.alignment = .leading
        repoStack.spacing = 6
        repoStack.translatesAutoresizingMaskIntoConstraints = false

        let selectedRepos = Set(currentConfig.allowedRepos)
        let repoButtons: [(repo: String, button: NSButton)] = availableRepos.map { repo in
            let button = NSButton(checkboxWithTitle: repo.fullName, target: nil, action: nil)
            button.state = selectedRepos.contains(repo.fullName) ? .on : .off
            return (repo.fullName, button)
        }

        if repoButtons.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "No GitHub repos available.")
            emptyLabel.textColor = .secondaryLabelColor
            repoStack.addArrangedSubview(emptyLabel)
        } else {
            for (_, button) in repoButtons {
                repoStack.addArrangedSubview(button)
            }
        }

        let repoDocument = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: max(264, repoButtons.count * 26)))
        repoDocument.addSubview(repoStack)
        NSLayoutConstraint.activate([
            repoStack.leadingAnchor.constraint(equalTo: repoDocument.leadingAnchor, constant: 8),
            repoStack.trailingAnchor.constraint(equalTo: repoDocument.trailingAnchor, constant: -8),
            repoStack.topAnchor.constraint(equalTo: repoDocument.topAnchor, constant: 8)
        ])
        scrollView.documentView = repoDocument
        accessory.addSubview(scrollView)

        let controller = CodexAgentSettingsDialogController(
            projectHomeLabel: projectHomeLabel,
            initialProjectHome: currentConfig.projectHome,
            repoButtons: repoButtons
        )
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
