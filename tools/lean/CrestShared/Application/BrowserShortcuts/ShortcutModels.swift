import Foundation

struct KeyCombination: Equatable, Sendable {
    let key: String
    let isSpecialKey: Bool
    let modifiers: ShortcutModifiers
}

struct ShortcutDefault: Equatable, Sendable {
    let platform: DevicePlatform
    let keys: KeyCombination
}

struct ShortcutBinding: Equatable, Sendable {
    let command: ShortcutCommand
    let keys: KeyCombination?
}

struct NumberedSelection: Equatable, Sendable {
    let command: ShortcutCommand
    let target: NumberedSelectionTarget
    let spaceID: UUID
    let tabID: UUID?
}
