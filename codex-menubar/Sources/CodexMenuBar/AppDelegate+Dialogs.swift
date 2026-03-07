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
    let targetID: String
    let mergerID: String
}

struct StaleSessionRemovalSelection {
    let olderThanDays: Int
    let sessionIDs: [String]
}

@MainActor
private final class StaleSessionRemovalController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let staleByDays: [Int: [CodexSessionsCLIClient.SessionOption]]
    private let dayOptions = [1, 3, 7]
    private let popup: NSPopUpButton
    private let tableView: NSTableView
    private let confirmButton: NSButton
    private var currentRows: [CodexSessionsCLIClient.SessionOption] = []

    init(staleByDays: [Int: [CodexSessionsCLIClient.SessionOption]],
         popup: NSPopUpButton,
         tableView: NSTableView,
         confirmButton: NSButton) {
        self.staleByDays = staleByDays
        self.popup = popup
        self.tableView = tableView
        self.confirmButton = confirmButton
    }

    func bootstrap(defaultDays: Int = 3) {
        popup.removeAllItems()
        for days in dayOptions {
            let label = days == 1 ? "1 day stale" : "\(days) days stale"
            popup.addItem(withTitle: label)
            popup.lastItem?.tag = days
        }
        if let index = dayOptions.firstIndex(of: defaultDays) {
            popup.selectItem(at: index)
        }
        popup.target = self
        popup.action = #selector(handleDaysChanged(_:))

        tableView.delegate = self
        tableView.dataSource = self
        reloadRows()
    }

    @objc func handleDaysChanged(_ sender: NSPopUpButton) {
        reloadRows()
    }

    func selectedDays() -> Int {
        let tag = popup.selectedTag()
        if tag > 0 {
            return tag
        }
        return 3
    }

    func selectedSessionIDs() -> [String] {
        tableView.selectedRowIndexes.compactMap { index in
            guard index >= 0 && index < currentRows.count else {
                return nil
            }
            return currentRows[index].id
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        currentRows.count
    }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard row >= 0, row < currentRows.count else {
            return nil
        }
        let identifier = NSUserInterfaceItemIdentifier("StaleSessionRow")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let textField = NSTextField(labelWithString: "")
            textField.lineBreakMode = .byTruncatingMiddle
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        let session = currentRows[row]
        cell.textField?.stringValue = "\(session.folder)  |  \(shortTimestamp(session.lastUpdatedAt))  |  \(session.title) (\(shortID(session.id)))"
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateConfirmButtonState()
    }

    private func reloadRows() {
        let days = selectedDays()
        currentRows = staleByDays[days] ?? []
        tableView.reloadData()
        if !currentRows.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        updateConfirmButtonState()
    }

    private func updateConfirmButtonState() {
        confirmButton.isEnabled = !selectedSessionIDs().isEmpty
    }

    private func shortID(_ fullID: String) -> String {
        String(fullID.prefix(8))
    }

    private func shortTimestamp(_ value: String) -> String {
        if value.count >= 19 {
            return String(value.prefix(19)).replacingOccurrences(of: "T", with: " ")
        }
        return value
    }
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

    func promptForStaleSessionRemoval(staleByDays: [Int: [CodexSessionsCLIClient.SessionOption]]) -> StaleSessionRemovalSelection? {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Remove Stale Sessions"
        alert.informativeText = """
Pick stale-window (1/3/7 days), then multi-select sessions ordered by folder. Click OK to permanently delete selected codex sessions.
"""

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 320))
        let quickLabel = NSTextField(labelWithString: "Quick Remove")
        quickLabel.frame = NSRect(x: 0, y: 294, width: 120, height: 18)
        accessory.addSubview(quickLabel)

        let staleDaysPopup = NSPopUpButton(frame: NSRect(x: 124, y: 288, width: 180, height: 26), pullsDown: false)
        accessory.addSubview(staleDaysPopup)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 620, height: 276))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        let tableView = NSTableView(frame: scrollView.bounds)
        tableView.allowsMultipleSelection = true
        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SessionColumn"))
        column.width = 610
        tableView.addTableColumn(column)
        scrollView.documentView = tableView
        accessory.addSubview(scrollView)

        alert.accessoryView = accessory
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        guard let confirmButton = alert.buttons.first else {
            return nil
        }

        let controller = StaleSessionRemovalController(staleByDays: staleByDays,
                                                       popup: staleDaysPopup,
                                                       tableView: tableView,
                                                       confirmButton: confirmButton)
        controller.bootstrap()

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return nil
        }

        let selectedIDs = controller.selectedSessionIDs()
        guard !selectedIDs.isEmpty else {
            return nil
        }

        return StaleSessionRemovalSelection(olderThanDays: controller.selectedDays(),
                                            sessionIDs: selectedIDs)
    }

    func promptForSessionMergeSelection(sessions: [CodexSessionsCLIClient.SessionOption]) -> SessionMergeSelection? {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Merge Sessions"
        alert.informativeText = """
Pick a Target session and a Merger session.

Codex will summarize the Merger session and append compacted non-actionable context into the Target session. After that succeeds, the Merger session is permanently deleted.
"""

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 92))

        let targetLabel = NSTextField(labelWithString: "Target")
        targetLabel.frame = NSRect(x: 0, y: 68, width: 120, height: 18)
        accessory.addSubview(targetLabel)

        let targetPopup = NSPopUpButton(frame: NSRect(x: 0, y: 44, width: 420, height: 24), pullsDown: false)
        for session in sessions {
            targetPopup.addItem(withTitle: "\(session.title) (\(session.id))")
        }
        accessory.addSubview(targetPopup)

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

        let targetIndex = targetPopup.indexOfSelectedItem
        let mergerIndex = mergerPopup.indexOfSelectedItem
        guard targetIndex >= 0, targetIndex < sessions.count, mergerIndex >= 0, mergerIndex < sessions.count else {
            return nil
        }
        guard targetIndex != mergerIndex else {
            showError(CodexSessionsCLIClient.Error(message: "Target and Merger must be different sessions."))
            return nil
        }

        return SessionMergeSelection(
            targetID: sessions[targetIndex].id,
            mergerID: sessions[mergerIndex].id
        )
    }
}
