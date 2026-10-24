enum BrowserChromeAccessibilityDirection {
    case previous
    case next
}

struct BrowserKeyboardModifierFlags: OptionSet, Equatable, Sendable {
    let rawValue: UInt

    static let command = BrowserKeyboardModifierFlags(rawValue: 1 << 0)
    static let control = BrowserKeyboardModifierFlags(rawValue: 1 << 1)
    static let option = BrowserKeyboardModifierFlags(rawValue: 1 << 2)
    static let shift = BrowserKeyboardModifierFlags(rawValue: 1 << 3)
}
