import Foundation

/// Commands, settings pages and the window's own actions, supplied by the
/// presenting platform shell, which palette rows other than addresses and
/// tabs perform.
@MainActor
struct BrowserCommandPaletteCommandRegistry {
    let commands: [ShortcutCommand]
    /// The settings pages the palette may open, by their settings name.
    let settingsPages: [PaletteSettingsPage]
    private let shortcutProvider: (ShortcutCommand) -> BrowserShortcut?
    private let performer: (ShortcutCommand) -> Void
    private let settingsOpener: (String) -> Void
    private let spaceSwitcher: (UUID) -> Void
    private let archiveReopener: (UUID) -> Void
    private let copier: (String) -> Void

    init(
        commands: [ShortcutCommand],
        settingsPages: [PaletteSettingsPage] = [],
        shortcut: @escaping (ShortcutCommand) -> BrowserShortcut? = { _ in nil },
        perform: @escaping (ShortcutCommand) -> Void,
        openSettings: @escaping (String) -> Void = { _ in },
        switchSpace: @escaping (UUID) -> Void = { _ in },
        reopenArchivedTab: @escaping (UUID) -> Void = { _ in },
        copy: @escaping (String) -> Void = { _ in }
    ) {
        self.commands = commands
        self.settingsPages = settingsPages
        shortcutProvider = shortcut
        performer = perform
        settingsOpener = openSettings
        spaceSwitcher = switchSpace
        archiveReopener = reopenArchivedTab
        copier = copy
    }

    /// The commands as the palette ranks them, with the titles this device
    /// shows for them.
    var paletteCommands: [PaletteCommand] {
        commands.map {
            PaletteCommand(
                command: $0, title: $0.title(locale: .current), sectionTitle: $0.section.title(locale: .current))
        }
    }

    func shortcut(for command: ShortcutCommand) -> BrowserShortcut? {
        shortcutProvider(command)
    }

    func perform(_ command: ShortcutCommand) {
        performer(command)
    }

    /// Opens Settings at the page the settings call `name`.
    func openSettings(_ name: String) {
        settingsOpener(name)
    }

    func switchSpace(_ id: UUID) {
        spaceSwitcher(id)
    }

    func reopenArchivedTab(_ id: UUID) {
        archiveReopener(id)
    }

    /// Copies `text` and says so in the window's notice.
    func copy(_ text: String) {
        copier(text)
    }
}
