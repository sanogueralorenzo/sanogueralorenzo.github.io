import WebKit

extension WKNavigationAction {
    /// How the person followed this navigation's link, for the core's link
    /// rules: whether they activated a link, whether it loads the whole page,
    /// the keys they held and whether they clicked the middle button.
    var linkGesture: LinkGesture {
        var held: ShortcutModifiers = []
        if modifierFlags.contains(.command) { held.insert(.command) }
        if modifierFlags.contains(.shift) { held.insert(.shift) }
        #if os(macOS)
            if modifierFlags.contains(.option) { held.insert(.option) }
            let middle = buttonNumber == 1 << 2
        #else
            if modifierFlags.contains(.alternate) { held.insert(.option) }
            let middle = buttonNumber.rawValue == 1 << 2
        #endif
        return LinkGesture(
            userActivated: navigationType == .linkActivated, topLevel: targetFrame?.isMainFrame ?? true,
            modifiers: held, middleClick: middle)
    }
}
