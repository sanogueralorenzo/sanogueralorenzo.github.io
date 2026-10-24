import CoreGraphics
import Foundation

enum BrowserShortcutSettingsPresentation {
    static let emptyShortcutGlyph = "—"
    static let searchPrompt: LocalizedStringResource = "Search shortcuts"
    static let resetCrest: LocalizedStringResource = "Reset All…"
    static let custom: LocalizedStringResource = "Custom"
    static let clearShortcut: LocalizedStringResource = "Clear Shortcut"
    static let resetToDefault: LocalizedStringResource = "Reset to Default"
    static let shortcutActions: LocalizedStringResource = "Shortcut Actions"
    static let shortcutAlreadyInUse: LocalizedStringResource =
        "Shortcut Already in Use"
    static let replaceExistingShortcut: LocalizedStringResource =
        "Replace Existing Shortcut"
    static let cancel: LocalizedStringResource = "Cancel"
    static let chooseAnotherShortcut: LocalizedStringResource =
        "Choose another shortcut."
    static let resetAllPrompt: LocalizedStringResource =
        "Reset all Crest shortcuts?"
    static let resetCrestShortcuts: LocalizedStringResource =
        "Reset Crest Shortcuts"
    static let resetAllDetail: LocalizedStringResource =
        "Every Crest command will return to its default shortcut."
    static let guidance: LocalizedStringResource =
        "Click a shortcut, then press the new keys."
    static let invalidShortcut: LocalizedStringResource =
        "Use a supported key with Command, Option, Control, or Shift."
    static let typeShortcut: LocalizedStringResource = "Type Shortcut"
    static let unassigned: LocalizedStringResource = "Unassigned"
    static let recorderHelp: LocalizedStringResource =
        "Click, then press the new shortcut"

    static func actionsAccessibilityLabel(
        title: String
    ) -> LocalizedStringResource {
        "Actions for \(title)"
    }

    static func recorderAccessibilityLabel(
        title: String
    ) -> LocalizedStringResource {
        "Shortcut for \(title)"
    }

}

extension BrowserShortcutPendingConflict {
    var messageResource: LocalizedStringResource {
        messageResource()
    }

    func messageResource(
        locale: Locale = .current
    ) -> LocalizedStringResource {
        let resource: LocalizedStringResource
        if conflictingCommands.count == 1,
            let command = conflictingCommands.first
        {
            resource =
                "\(shortcut.displayString(locale: locale)) is assigned to \(command.title(locale: locale)). Replacing it will clear the shortcut from that command."
        } else {
            let titles = BrowserShortcutLocalization.list(
                conflictingCommands.map { $0.title(locale: locale) },
                locale: locale
            )
            resource =
                "\(shortcut.displayString(locale: locale)) is assigned to \(titles). Replacing it will clear the shortcut from those commands."
        }
        return BrowserShortcutLocalization.resource(
            resource,
            locale: locale
        )
    }
}

extension BrowserShortcutValidationIssue {
    var messageResource: LocalizedStringResource {
        messageResource()
    }

    func messageResource(
        locale: Locale = .current
    ) -> LocalizedStringResource {
        let resource: LocalizedStringResource =
            switch self {
            case .invalidShortcut:
                BrowserShortcutSettingsPresentation.invalidShortcut
            case .reservedByCrest(let shortcut, let commands):
                "\(shortcut.displayString(locale: locale)) is reserved by Crest for \(localizedCommandList(commands, locale: locale))."
            }
        return BrowserShortcutLocalization.resource(resource, locale: locale)
    }

    private func localizedCommandList(
        _ commands: [ShortcutCommand],
        locale: Locale
    ) -> String {
        BrowserShortcutLocalization.list(
            commands.map { $0.title(locale: locale) },
            locale: locale
        )
    }
}

enum BrowserShortcutSettingsAccessibilityID {
    static let search = "shortcut-search"
    static let resetAll = "shortcut-reset-all"
    static let validationMessage = "shortcut-validation-message"
    static let list = "shortcut-list"
    static let recorderPrefix = "shortcut-"
}

enum BrowserShortcutSettingsMetrics {
    static let contentSpacing: CGFloat = 12
    static let controlSpacing: CGFloat = 10
    static let rowSpacing: CGFloat = 12
    static let rowVerticalPadding: CGFloat = 3
    static let spacePickerWidth: CGFloat = 150
    static let recorderWidth: CGFloat = 116
    static let recorderHeight: CGFloat = 28
    static let actionSize: CGFloat = 28
    static let recorderFontSize: CGFloat = 13
}
