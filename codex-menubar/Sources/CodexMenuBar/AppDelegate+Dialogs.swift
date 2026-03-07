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

struct SessionMergeSelection {
    let sourceID: String
    let mergerID: String
}

extension AppDelegate {
    func promptForProfileName(existingProfiles: [String]) -> String? {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Add Profile"
        alert.informativeText = "Current Codex Auth will be linked to this profile."

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

    func confirmRemoveStaleSessions(staleSessionCount: Int, olderThanDays: Int) -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Remove Stale Sessions"
        alert.informativeText = """
This will permanently delete \(staleSessionCount) codex sessions last updated more than \(olderThanDays) day(s) ago.

This action cannot be undone.
"""
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        return alert.runModal() == .alertFirstButtonReturn
    }

    func promptForSessionMergeSelection(sessions: [CodexSessionsCLIClient.SessionOption]) -> SessionMergeSelection? {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Merge Sessions"
        alert.informativeText = """
Pick a Source session and a Merger session.

Codex will summarize the Merger session and append compacted non-actionable context into the Source session. After that succeeds, the Merger session is permanently deleted.
"""

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 92))

        let sourceLabel = NSTextField(labelWithString: "Source")
        sourceLabel.frame = NSRect(x: 0, y: 68, width: 120, height: 18)
        accessory.addSubview(sourceLabel)

        let sourcePopup = NSPopUpButton(frame: NSRect(x: 0, y: 44, width: 420, height: 24), pullsDown: false)
        for session in sessions {
            sourcePopup.addItem(withTitle: "\(session.title) (\(session.id))")
        }
        accessory.addSubview(sourcePopup)

        let mergerLabel = NSTextField(labelWithString: "Merger")
        mergerLabel.frame = NSRect(x: 0, y: 22, width: 120, height: 18)
        accessory.addSubview(mergerLabel)

        let mergerPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 420, height: 24), pullsDown: false)
        for session in sessions {
            mergerPopup.addItem(withTitle: "\(session.title) (\(session.id))")
        }
        if sessions.count > 1 {
            mergerPopup.selectItem(at: 1)
        }
        accessory.addSubview(mergerPopup)

        alert.accessoryView = accessory
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return nil
        }

        let sourceIndex = sourcePopup.indexOfSelectedItem
        let mergerIndex = mergerPopup.indexOfSelectedItem
        guard sourceIndex >= 0, sourceIndex < sessions.count, mergerIndex >= 0, mergerIndex < sessions.count else {
            return nil
        }
        guard sourceIndex != mergerIndex else {
            showError(CodexSessionsCLIClient.Error(message: "Source and Merger must be different sessions."))
            return nil
        }

        return SessionMergeSelection(
            sourceID: sessions[sourceIndex].id,
            mergerID: sessions[mergerIndex].id
        )
    }
}
