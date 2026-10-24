extension ShortcutSpecialKey {
    init?(keyCode rawKeyCode: UInt16) {
        guard
            let keyCode = BrowserShortcutHardwareKeyCode(
                rawValue: rawKeyCode
            )
        else {
            return nil
        }

        self =
            switch keyCode {
            case .tab: .tab
            case .leftArrow: .leftArrow
            case .rightArrow: .rightArrow
            case .upArrow: .upArrow
            case .downArrow: .downArrow
            case .escape: .escape
            case .returnKey, .keypadEnter: .returnKey
            case .delete: .delete
            case .forwardDelete: .forwardDelete
            case .home: .home
            case .end: .end
            case .pageUp: .pageUp
            case .pageDown: .pageDown
            case .space: .space
            case .f1: .f1
            case .f2: .f2
            case .f3: .f3
            case .f4: .f4
            case .f5: .f5
            case .f6: .f6
            case .f7: .f7
            case .f8: .f8
            case .f9: .f9
            case .f10: .f10
            case .f11: .f11
            case .f12: .f12
            case .f13: .f13
            case .f14: .f14
            case .f15: .f15
            case .f16: .f16
            case .f17: .f17
            case .f18: .f18
            case .f19: .f19
            case .f20: .f20
            }
    }
}
