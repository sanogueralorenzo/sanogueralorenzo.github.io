import Foundation

struct BrowserShortcutPresentationCatalog: BrowserShortcutSearchProviding {
    let locale: Locale

    init(locale: Locale = .current) {
        self.locale = locale
    }

    func matches(
        _ command: ShortcutCommand,
        currentShortcut: BrowserShortcut?,
        query: String
    ) -> Bool {
        let searchTerms = command.searchTerms.map { BrowserShortcutLocalization.string($0, locale: locale) }
        return BrowserShortcutSearchDocument(
            fields: [
                command.title(locale: locale),
                command.section.title(locale: locale),
                searchTerms,
                currentShortcut?.spokenDescription(locale: locale)
                    ?? BrowserShortcutLocalization.string(
                        "unassigned none no shortcut",
                        locale: locale
                    ),
            ].compactMap { $0 }
        ).matches(query)
    }
}

enum BrowserShortcutLocalization {
    static func string(
        _ resource: LocalizedStringResource,
        locale: Locale
    ) -> String {
        String(localized: Self.resource(resource, locale: locale))
    }

    static func resource(
        _ resource: LocalizedStringResource,
        locale: Locale
    ) -> LocalizedStringResource {
        var localizedResource = resource
        localizedResource.locale = locale
        return localizedResource
    }

    static func list(
        _ values: [String],
        locale: Locale
    ) -> String {
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: values)
            ?? values.joined(separator: ", ")
    }
}

extension BrowserShortcut {
    var displayString: String {
        displayString()
    }

    func displayString(locale: Locale = .current) -> String {
        modifiers.displayString + key.displayString(locale: locale)
    }

    func spokenDescription(locale: Locale = .current) -> String {
        [
            modifiers.spokenDescription(locale: locale),
            key.spokenDescription(locale: locale),
        ].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var spokenDescription: String {
        spokenDescription()
    }
}

extension ShortcutCommand {
    /// The title in `locale`, for text composed around it.
    func title(locale: Locale = .current) -> String {
        BrowserShortcutLocalization.string(self.title, locale: locale)
    }

    func matches(search query: String) -> Bool {
        BrowserShortcutPresentationCatalog().matches(
            self,
            currentShortcut: defaultShortcut,
            query: query
        )
    }

    func matches(
        search query: String,
        currentShortcut: BrowserShortcut?
    ) -> Bool {
        BrowserShortcutPresentationCatalog().matches(
            self,
            currentShortcut: currentShortcut,
            query: query
        )
    }
}

extension BrowserShortcutKey {
    var displayString: String {
        displayString()
    }

    func displayString(locale: Locale = .current) -> String {
        switch self {
        case .character(let character):
            String(character).uppercased()
        case .special(let key):
            key.displayString(locale: locale)
        }
    }

    func spokenDescription(locale: Locale = .current) -> String {
        switch self {
        case .character(let character):
            String(character).lowercased()
        case .special(let key):
            key.spokenDescription(locale: locale)
        }
    }

    var spokenDescription: String {
        spokenDescription()
    }
}

extension ShortcutModifiers {
    var displayString: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }

    func spokenDescription(locale: Locale = .current) -> String {
        let resources: [LocalizedStringResource] = [
            contains(.control) ? "control" : nil,
            contains(.option) ? "option" : nil,
            contains(.shift) ? "shift" : nil,
            contains(.command) ? "command" : nil,
        ].compactMap { $0 }
        return resources.map { resource in
            BrowserShortcutLocalization.string(resource, locale: locale)
        }.joined(separator: " ")
    }

    var spokenDescription: String {
        spokenDescription()
    }
}

extension ShortcutSection {
    /// The title in `locale`, for text composed around it.
    func title(locale: Locale = .current) -> String {
        BrowserShortcutLocalization.string(self.title, locale: locale)
    }
}

extension ShortcutSpecialKey {
    var displayString: String {
        displayString()
    }

    /// The key's glyph, or its name where no glyph stands for it.
    func displayString(locale: Locale = .current) -> String {
        glyph ?? title.map { BrowserShortcutLocalization.string($0, locale: locale) } ?? name
    }

    /// How assistive technology reads the key; a key without a spoken name is
    /// read by its name.
    func spokenDescription(locale: Locale = .current) -> String {
        spokenName.map { BrowserShortcutLocalization.string($0, locale: locale) } ?? name
    }

    var spokenDescription: String {
        spokenDescription()
    }
}

extension BrowserShortcutStore {
    func commands(matching query: String) -> [ShortcutCommand] {
        let catalog = BrowserShortcutPresentationCatalog()
        return offeredCommands.filter {
            catalog.matches(
                $0,
                currentShortcut: shortcut(for: $0),
                query: query
            )
        }
    }
}
