import AppKit

extension BrowserKeyboardModifierFlags {
    init(_ modifiers: NSEvent.ModifierFlags) {
        var resolved: BrowserKeyboardModifierFlags = []
        if modifiers.contains(.command) { resolved.insert(.command) }
        if modifiers.contains(.control) { resolved.insert(.control) }
        if modifiers.contains(.option) { resolved.insert(.option) }
        if modifiers.contains(.shift) { resolved.insert(.shift) }
        self = resolved
    }
}
