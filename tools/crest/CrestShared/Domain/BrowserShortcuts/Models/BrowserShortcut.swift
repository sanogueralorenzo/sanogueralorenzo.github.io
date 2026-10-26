struct BrowserShortcut: Codable, Equatable, Hashable, Sendable {
    let key: BrowserShortcutKey
    let modifiers: ShortcutModifiers

    var isValid: Bool {
        !modifiers.intersection(.supported).isEmpty
    }
}

extension BrowserShortcut {
    /// The chord a catalog default names. The catalog names a special key by
    /// its `ShortcutSpecialKey` name, and every other key as the one character
    /// it types.
    init(_ keys: KeyCombination) {
        let key: BrowserShortcutKey
        if keys.isSpecialKey {
            guard let special = ShortcutSpecialKey.named(keys.key) else {
                preconditionFailure("The shortcut catalog names an unknown special key \(keys.key)")
            }
            key = .special(special)
        } else {
            guard keys.key.count == 1, let character = keys.key.first else {
                preconditionFailure("The shortcut catalog's key \(keys.key) is not one character")
            }
            key = .character(character)
        }
        self.init(key: key, modifiers: keys.modifiers)
    }

    /// The keys a command is bound to in the core's read model, or nil for
    /// keys no shortcut here can spell.
    init?(boundKeys keys: KeyCombination) {
        if keys.isSpecialKey {
            guard let special = ShortcutSpecialKey.named(keys.key) else { return nil }
            self.init(key: .special(special), modifiers: keys.modifiers)
        } else {
            guard keys.key.count == 1, let character = keys.key.first else { return nil }
            self.init(key: .character(character), modifiers: keys.modifiers)
        }
    }

    /// The shortcut as the core's rules read it.
    var keys: KeyCombination {
        switch key {
        case .character(let character):
            KeyCombination(key: String(character), isSpecialKey: false, modifiers: modifiers)
        case .special(let special):
            KeyCombination(key: special.name, isSpecialKey: true, modifiers: modifiers)
        }
    }
}

enum BrowserShortcutKey: Codable, Hashable, Sendable {
    case character(Character)
    case special(ShortcutSpecialKey)

    private enum CodingKeys: String, CodingKey {
        case character
        case special
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(
            String.self,
            forKey: .character
        ),
            value.count == 1,
            let character = value.first
        {
            self = .character(character)
            return
        }
        self = .special(
            try container.decode(
                ShortcutSpecialKey.self,
                forKey: .special
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .character(let character):
            try container.encode(String(character), forKey: .character)
        case .special(let key):
            try container.encode(key, forKey: .special)
        }
    }
}

/// A modifier mask persists as its raw bits.
extension ShortcutModifiers: Codable, Hashable {
    static let supported: ShortcutModifiers = [
        .command,
        .option,
        .control,
        .shift,
    ]
}

extension ShortcutSection: Identifiable {
    var id: String { name }
}
