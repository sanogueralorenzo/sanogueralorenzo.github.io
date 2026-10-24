import Foundation

/// The storage boundary shared by every browser entity that can wear an emoji.
///
/// An emoji is stored in the same `symbol` slot as an SF Symbol, with a prefix
/// that makes the two vocabularies unambiguous. Normalization selects one
/// Swift `Character`, not one Unicode scalar, so flags, skin tones, keycaps,
/// and zero-width-joiner sequences survive as the complete grapheme a person
/// picked.
enum BrowserIconSymbol {
    static func symbol(forEmoji input: String) -> String {
        guard let emoji = normalizedEmoji(input) else { return input }
        return TabIconMode.emojiPrefix + emoji
    }

    static func emoji(from symbol: String) -> String? {
        guard symbol.hasPrefix(TabIconMode.emojiPrefix) else { return nil }
        return normalizedEmoji(String(symbol.dropFirst(TabIconMode.emojiPrefix.count)))
    }

    static func normalizedEmoji(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let character = trimmed.first else { return nil }
        let candidate = String(character)
        let scalars = candidate.unicodeScalars
        let isEmoji = scalars.contains { scalar in
            scalar.properties.isEmojiPresentation
                || scalar.value == 0xFE0F
                || scalar.value == 0x20E3
        }
        return isEmoji ? candidate : nil
    }
}
