import Foundation

/// How the palette runs one of the core's activations: each names the
/// activation it runs and does it to a row in a palette, answering whether it
/// ran. The core says what each row kind's activation is; the platform's
/// palette context supplies what only it can do, such as running a command.
@MainActor
struct BrowserCommandPaletteActivation {
    // MARK: - Static Variables

    static let switchesToTab = BrowserCommandPaletteActivation(.switchesToTab) { row, palette in
        palette.switchToTab(row.tabID)
    }
    static let opensAddress = BrowserCommandPaletteActivation(.opensAddress) { row, palette in
        palette.open(row.address, where: palette.opening(for: row))
    }
    static let searches = BrowserCommandPaletteActivation(.searches) { row, palette in
        palette.open(row.address, where: palette.opening(for: row))
    }
    static let runsCommand = BrowserCommandPaletteActivation(.runsCommand) { row, palette in
        guard let command = row.command, let commands = palette.commands else { return false }
        commands.perform(command)
        return true
    }
    static let opensSettingsPage = BrowserCommandPaletteActivation(.opensSettingsPage) { row, palette in
        guard let page = row.settingsPage, let commands = palette.commands else { return false }
        commands.openSettings(page)
        return true
    }
    static let showsSpace = BrowserCommandPaletteActivation(.showsSpace) { row, palette in
        guard let spaceID = row.subjectID, let commands = palette.commands else { return false }
        commands.switchSpace(spaceID)
        return true
    }
    static let reopensArchivedTab = BrowserCommandPaletteActivation(.reopensArchivedTab) { row, palette in
        guard let tabID = row.subjectID, let commands = palette.commands else { return false }
        commands.reopenArchivedTab(tabID)
        return true
    }
    static let copiesAnswer = BrowserCommandPaletteActivation(.copiesAnswer) { row, palette in
        guard let commands = palette.commands else { return false }
        commands.copy(row.title)
        return true
    }
    static let entersScope = BrowserCommandPaletteActivation(.entersScope) { row, palette in
        guard let scope = row.scope else { return false }
        palette.enter(scope)
        return true
    }

    static let all = [
        switchesToTab, opensAddress, searches, runsCommand, opensSettingsPage, showsSpace, reopensArchivedTab,
        copiesAnswer, entersScope,
    ]

    // MARK: - Variables

    /// The core's activation this runs.
    let activation: PaletteActivation

    /// Runs a row in a palette, answering whether it ran.
    let run: @MainActor (PaletteRow, BrowserCommandPaletteModel) -> Bool

    // MARK: - Initializers

    private init(
        _ activation: PaletteActivation, run: @escaping @MainActor (PaletteRow, BrowserCommandPaletteModel) -> Bool
    ) {
        self.activation = activation
        self.run = run
    }

    // MARK: - Actions - Lookup

    /// The palette's way of running `activation`, or nil for one it cannot run.
    static func of(_ activation: PaletteActivation) -> BrowserCommandPaletteActivation? {
        all.first { $0.activation == activation }
    }
}
