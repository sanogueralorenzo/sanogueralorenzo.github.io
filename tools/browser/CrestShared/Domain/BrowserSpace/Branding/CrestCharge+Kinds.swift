import Foundation

/// What a crest bears: a figure from the heraldic set, any system symbol, an
/// emoji, a monogram of up to two letters, or nothing.
extension CrestCharge {
    // MARK: - Static Variables

    /// A charge that draws nothing in place of the heraldic figure.
    static let none = CrestCharge(kind: .none, symbol: nil, text: nil, style: nil)

    // MARK: - Initializers

    static func heraldic(_ symbol: CrestSymbol) -> CrestCharge {
        CrestCharge(kind: .heraldic, symbol: symbol, text: nil, style: nil)
    }

    static func system(_ name: String) -> CrestCharge {
        CrestCharge(kind: .system, symbol: nil, text: name, style: nil)
    }

    static func emoji(_ emoji: String) -> CrestCharge {
        CrestCharge(kind: .emoji, symbol: nil, text: emoji, style: nil)
    }

    static func monogram(_ letters: String, _ style: CrestMonogramStyle) -> CrestCharge {
        CrestCharge(kind: .monogram, symbol: nil, text: letters, style: style)
    }
}
