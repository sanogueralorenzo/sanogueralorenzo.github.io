import SwiftUI

extension ShortcutSpecialKey {
    // MARK: - Variables

    /// The key as SwiftUI binds it. A function key is the platform's function
    /// key character for its number.
    var keyEquivalent: KeyEquivalent {
        if let functionKeyNumber {
            let scalar = UnicodeScalar(Self.firstFunctionKeyScalarValue + functionKeyNumber)
            return scalar.map { KeyEquivalent(Character($0)) } ?? .escape
        }
        return Self.keyEquivalents[self] ?? .escape
    }

    private static let firstFunctionKeyScalarValue = 0xF703

    /// SwiftUI's own key for each special key that is not a function key.
    private static let keyEquivalents: [ShortcutSpecialKey: KeyEquivalent] = [
        .tab: .tab, .leftArrow: .leftArrow, .rightArrow: .rightArrow, .upArrow: .upArrow, .downArrow: .downArrow,
        .escape: .escape, .returnKey: .return, .delete: .delete, .forwardDelete: .deleteForward, .home: .home,
        .end: .end, .pageUp: .pageUp, .pageDown: .pageDown, .space: .space,
    ]
}
