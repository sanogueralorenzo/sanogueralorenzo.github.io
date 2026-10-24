import Foundation

/// A key an agent may press, as the DOM names it: a named key such as Enter
/// or ArrowDown, or one character, which the engine delivers as the person's
/// keyboard would.
struct BrowserAgentKey {
    // MARK: - Static Variables

    static let enter = Self(key: "Enter", code: "Enter", keyCode: 13, text: "\r")
    static let tab = Self(key: "Tab", code: "Tab", keyCode: 9, text: nil)
    static let escape = Self(key: "Escape", code: "Escape", keyCode: 27, text: nil)
    static let backspace = Self(key: "Backspace", code: "Backspace", keyCode: 8, text: nil)
    static let delete = Self(key: "Delete", code: "Delete", keyCode: 46, text: nil)
    static let space = Self(key: " ", code: "Space", keyCode: 32, text: " ")
    static let arrowUp = Self(key: "ArrowUp", code: "ArrowUp", keyCode: 38, text: nil)
    static let arrowDown = Self(key: "ArrowDown", code: "ArrowDown", keyCode: 40, text: nil)
    static let arrowLeft = Self(key: "ArrowLeft", code: "ArrowLeft", keyCode: 37, text: nil)
    static let arrowRight = Self(key: "ArrowRight", code: "ArrowRight", keyCode: 39, text: nil)
    static let home = Self(key: "Home", code: "Home", keyCode: 36, text: nil)
    static let end = Self(key: "End", code: "End", keyCode: 35, text: nil)
    static let pageUp = Self(key: "PageUp", code: "PageUp", keyCode: 33, text: nil)
    static let pageDown = Self(key: "PageDown", code: "PageDown", keyCode: 34, text: nil)

    static let named: [Self] =
        [
            enter, tab, escape, backspace, delete, space, arrowUp, arrowDown, arrowLeft, arrowRight, home, end, pageUp,
            pageDown,
        ]
        + (1...12).map { Self(key: "F\($0)", code: "F\($0)", keyCode: 111 + $0, text: nil) }

    // MARK: - Variables

    let key: String
    let code: String
    let keyCode: Int
    let text: String?

    /// The key as the engine contract carries it.
    var pageKey: PageKey { PageKey(key: key, code: code, keyCode: keyCode, text: text) }

    // MARK: - Actions - Lookup

    /// The key `name` names: a named key, whatever its case, or a single
    /// character; nil for anything else.
    static func named(_ name: String) -> Self? {
        if let key = named.first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame || $0.code == name }) {
            return key
        }
        if name == "Space" { return space }
        guard name.count == 1, let character = name.first else { return nil }
        let upper = character.uppercased()
        let code: String
        let keyCode: Int
        if character.isLetter, let ascii = upper.unicodeScalars.first?.value, ascii < 128 {
            code = "Key\(upper)"
            keyCode = Int(ascii)
        } else if character.isNumber, let ascii = character.unicodeScalars.first?.value, ascii < 128 {
            code = "Digit\(character)"
            keyCode = Int(ascii)
        } else {
            code = ""
            keyCode = 0
        }
        return Self(key: name, code: code, keyCode: keyCode, text: name)
    }
}
