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
    private struct DisplayRow {
        let title: String
        let meta: String
    }

    private let staleByDays: [Int: [CodexSessionsCLIClient.SessionOption]]
    private let dayOptions = [0, 1, 3, 7]
    private let segmentedControl: NSSegmentedControl
    private let tableView: NSTableView
    private let confirmButton: NSButton
    private var currentRows: [CodexSessionsCLIClient.SessionOption] = []
    private var displayRows: [DisplayRow] = []

    init(staleByDays: [Int: [CodexSessionsCLIClient.SessionOption]],
         segmentedControl: NSSegmentedControl,
         tableView: NSTableView,
         confirmButton: NSButton) {
        self.staleByDays = staleByDays
        self.segmentedControl = segmentedControl
        self.tableView = tableView
        self.confirmButton = confirmButton
    }

    func bootstrap(defaultDays: Int = 0) {
        segmentedControl.segmentCount = dayOptions.count
        for (index, days) in dayOptions.enumerated() {
            segmentedControl.setLabel(days == 0 ? "All" : "\(days)d", forSegment: index)
        }
        if let index = dayOptions.firstIndex(of: defaultDays) {
            segmentedControl.selectedSegment = index
        } else {
            segmentedControl.selectedSegment = 1
        }
        segmentedControl.target = self
        segmentedControl.action = #selector(handleDaysChanged(_:))

        tableView.delegate = self
        tableView.dataSource = self
        reloadRows()
    }

    @objc func handleDaysChanged(_ sender: NSSegmentedControl) {
        reloadRows()
    }

    func selectedDays() -> Int {
        let index = segmentedControl.selectedSegment
        if index >= 0 && index < dayOptions.count {
            return dayOptions[index]
        }
        return 0
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
        guard row >= 0, row < displayRows.count else {
            return nil
        }
        let identifier = NSUserInterfaceItemIdentifier("StaleSessionRow")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            let titleField = NSTextField(labelWithString: "")
            titleField.tag = 1001
            titleField.font = .systemFont(ofSize: 12, weight: .medium)
            titleField.lineBreakMode = .byTruncatingTail
            titleField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(titleField)

            let metaField = NSTextField(labelWithString: "")
            metaField.tag = 1002
            metaField.font = .systemFont(ofSize: 11)
            metaField.textColor = .secondaryLabelColor
            metaField.lineBreakMode = .byTruncatingTail
            metaField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(metaField)

            NSLayoutConstraint.activate([
                titleField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                titleField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                titleField.topAnchor.constraint(equalTo: cell.topAnchor, constant: 3),
                metaField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                metaField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                metaField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 1),
                metaField.bottomAnchor.constraint(lessThanOrEqualTo: cell.bottomAnchor, constant: -3)
            ])
        }

        let rowModel = displayRows[row]
        (cell.viewWithTag(1001) as? NSTextField)?.stringValue = rowModel.title
        (cell.viewWithTag(1002) as? NSTextField)?.stringValue = rowModel.meta
        return cell
    }

    func tableView(_ tableView: NSTableView,
                   selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet) -> IndexSet {
        guard let event = NSApp.currentEvent else {
            return proposedSelectionIndexes
        }

        if event.type == .leftMouseDown {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if !modifiers.contains(.command) && !modifiers.contains(.shift) {
                var toggled = tableView.selectedRowIndexes
                for row in proposedSelectionIndexes {
                    if toggled.contains(row) {
                        toggled.remove(row)
                    } else {
                        toggled.insert(row)
                    }
                }
                return toggled
            }
        }

        return proposedSelectionIndexes
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateConfirmButtonState()
    }

    @objc func selectAllRows(_ sender: Any?) {
        guard !currentRows.isEmpty else {
            return
        }
        tableView.selectRowIndexes(IndexSet(integersIn: 0..<currentRows.count), byExtendingSelection: false)
        updateConfirmButtonState()
    }

    @objc func clearSelection(_ sender: Any?) {
        tableView.deselectAll(nil)
        updateConfirmButtonState()
    }

    private func reloadRows() {
        let days = selectedDays()
        currentRows = staleByDays[days] ?? []
        displayRows = currentRows.map {
            DisplayRow(
                title: $0.title,
                meta: "\($0.folder) • \(shortTimestamp($0.lastUpdatedAt)) • \(shortID($0.id))"
            )
        }
        tableView.reloadData()
        if !currentRows.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
        updateConfirmButtonState()
    }

    private func updateConfirmButtonState() {
        let count = selectedSessionIDs().count
        confirmButton.title = "Delete \(count)"
        confirmButton.isEnabled = count > 0
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
        alert.messageText = "Remove Threads"
        alert.informativeText = "Select threads to permanently delete. Use All to view every active thread."

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 320))
        let staleWindowLabel = NSTextField(labelWithString: "Stale Window")
        staleWindowLabel.frame = NSRect(x: 0, y: 294, width: 90, height: 18)
        accessory.addSubview(staleWindowLabel)

        let staleWindowControl = NSSegmentedControl(frame: NSRect(x: 94, y: 288, width: 170, height: 26))
        staleWindowControl.segmentStyle = .rounded
        staleWindowControl.trackingMode = .selectOne
        accessory.addSubview(staleWindowControl)

        let selectAllButton = NSButton(frame: NSRect(x: 274, y: 288, width: 94, height: 26))
        selectAllButton.bezelStyle = .rounded
        selectAllButton.title = "Select All"
        accessory.addSubview(selectAllButton)

        let clearButton = NSButton(frame: NSRect(x: 374, y: 288, width: 74, height: 26))
        clearButton.bezelStyle = .rounded
        clearButton.title = "Clear"
        accessory.addSubview(clearButton)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 620, height: 276))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        let tableView = NSTableView(frame: scrollView.bounds)
        tableView.allowsMultipleSelection = true
        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 36
        tableView.intercellSpacing = NSSize(width: 0, height: 1)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SessionColumn"))
        column.width = 610
        tableView.addTableColumn(column)
        scrollView.documentView = tableView
        accessory.addSubview(scrollView)

        alert.accessoryView = accessory
        alert.addButton(withTitle: "Delete 0")
        alert.addButton(withTitle: "Cancel")

        guard let confirmButton = alert.buttons.first else {
            return nil
        }

        let controller = StaleSessionRemovalController(staleByDays: staleByDays,
                                                       segmentedControl: staleWindowControl,
                                                       tableView: tableView,
                                                       confirmButton: confirmButton)
        selectAllButton.target = controller
        selectAllButton.action = #selector(StaleSessionRemovalController.selectAllRows(_:))
        clearButton.target = controller
        clearButton.action = #selector(StaleSessionRemovalController.clearSelection(_:))
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
        alert.messageText = "Merge Threads"
        alert.informativeText = """
Pick a Target thread and a Merger thread.

Codex will summarize the Merger thread and append compacted non-actionable context into the Target thread. After that succeeds, the Merger thread is permanently deleted.
"""

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 92))

        let targetLabel = NSTextField(labelWithString: "Target")
        targetLabel.frame = NSRect(x: 0, y: 68, width: 120, height: 18)
        accessory.addSubview(targetLabel)

        let targetPopup = NSPopUpButton(frame: NSRect(x: 0, y: 44, width: 420, height: 24), pullsDown: false)
        for session in sessions {
            targetPopup.addItem(withTitle: session.title)
        }
        accessory.addSubview(targetPopup)

        let mergerLabel = NSTextField(labelWithString: "Merger")
        mergerLabel.frame = NSRect(x: 0, y: 22, width: 120, height: 18)
        accessory.addSubview(mergerLabel)

        let mergerPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 420, height: 24), pullsDown: false)
        for session in sessions {
            mergerPopup.addItem(withTitle: session.title)
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
            showError(CodexSessionsCLIClient.Error(message: "Target and Merger must be different threads."))
            return nil
        }

        return SessionMergeSelection(
            targetID: sessions[targetIndex].id,
            mergerID: sessions[mergerIndex].id
        )
    }
}
