import Foundation
import Observation

@Observable
@MainActor
final class BrowserShortcutSettingsModel {
    private let shortcuts: BrowserShortcutStore

    var searchText = ""
    var validationIssue: BrowserShortcutValidationIssue?
    var pendingConflict: BrowserShortcutPendingConflict?

    @ObservationIgnored private var searchProvider: any BrowserShortcutSearchProviding

    init(
        shortcuts: BrowserShortcutStore,
        searchProvider: any BrowserShortcutSearchProviding
    ) {
        self.shortcuts = shortcuts
        self.searchProvider = searchProvider
    }

    var isPresentingConflict: Bool {
        get { pendingConflict != nil }
        set {
            if !newValue {
                pendingConflict = nil
            }
        }
    }

    var hasCrestCustomizations: Bool {
        shortcuts.hasCustomizations
    }

    func shortcut(
        for command: ShortcutCommand
    ) -> BrowserShortcut? {
        shortcuts.shortcut(for: command)
    }

    func isCustomized(_ command: ShortcutCommand) -> Bool {
        shortcuts.isCustomized(command)
    }

    var commandGroups: [BrowserShortcutCommandGroup] {
        let matches = shortcuts.offeredCommands.filter {
            searchProvider.matches(
                $0,
                currentShortcut: shortcuts.shortcut(for: $0),
                query: searchText
            )
        }
        return ShortcutSection.all.compactMap { section in
            let commands = matches.filter { $0.section == section }
            guard !commands.isEmpty else { return nil }
            return BrowserShortcutCommandGroup(
                section: section,
                commands: commands
            )
        }
    }

    func updateSearchProvider(
        _ searchProvider: any BrowserShortcutSearchProviding
    ) {
        self.searchProvider = searchProvider
    }

    func record(
        _ shortcut: BrowserShortcut?,
        for command: ShortcutCommand
    ) {
        guard let shortcut else {
            shortcuts.clearShortcut(for: command)
            validationIssue = nil
            return
        }

        shortcuts.assign(shortcut, to: command).apply(to: self, recording: shortcut, for: command)
    }

    func replacePendingConflict() {
        guard let pendingConflict else { return }
        _ = shortcuts.reassign(
            pendingConflict.shortcut,
            to: pendingConflict.command
        )
        self.pendingConflict = nil
        validationIssue = nil
    }

    func cancelPendingConflict() {
        pendingConflict = nil
    }

    func reset(_ command: ShortcutCommand) {
        shortcuts.reset(command)
        validationIssue = nil
    }

    func resetAllCrestShortcuts() {
        shortcuts.resetAll()
        validationIssue = nil
    }

    func reportInvalidShortcut() {
        validationIssue = .invalidShortcut
    }

}
