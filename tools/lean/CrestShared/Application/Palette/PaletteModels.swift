import Foundation

struct AddressCompletion: Equatable, Sendable {
    let typed: String
    let suffix: String
    let accepted: String
}

struct PaletteAnswer: Equatable, Sendable {
    let groups: [PaletteGroup]
    let completion: AddressCompletion?
    let suggestionAddress: String?
    let offeredScope: PaletteScope?
    let entry: PaletteEntry?
}

struct PaletteCommand: Equatable, Sendable {
    var command: ShortcutCommand
    var title: String
    var sectionTitle: String
}

struct PaletteEntry: Equatable, Sendable {
    let scope: PaletteScope
    let text: String
}

struct PaletteGroup: Equatable, Sendable {
    let section: PaletteSection
    let rows: [PaletteRow]
}

struct PaletteRow: Equatable, Sendable {
    let kind: PaletteRowKind
    let title: String
    let subtitle: String
    let symbol: String
    let subjectID: UUID?
    let tabID: UUID?
    let address: String?
    let command: ShortcutCommand?
    let provider: SearchProvider?
    let settingsPage: String?
    let scope: PaletteScope?
    var reason: PaletteReason?
}

struct PaletteSettingsPage: Equatable, Sendable {
    var name: String
    var title: String
    var terms: String
}

struct PaletteSuggestions: Equatable, Sendable {
    let windowID: UUID
    let text: String
    let commands: [PaletteCommand]
    let settingsPages: [PaletteSettingsPage]
    let remote: [String]
    let scope: PaletteScope?
    let allowsCompletion: Bool
}
