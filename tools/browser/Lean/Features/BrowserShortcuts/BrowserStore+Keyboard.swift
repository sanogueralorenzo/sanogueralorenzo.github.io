import AppKit

extension BrowserStore {
    func handleKeyboard(_ event: NSEvent) -> Bool {
        if event.type == .keyDown {
            if event.keyCode == 53 && recentSwitcherPresented {
                recentSwitcherPresented = false
                return true
            }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if handleSidebarSelectionKey(event, modifiers: modifiers) { return true }
            if let value = event.charactersIgnoringModifiers?.first?.wholeNumberValue, (1...9).contains(value) {
                if modifiers == .command {
                    let tabs = sidebarOrder
                    if tabs.indices.contains(value - 1) { selectTab(tabs[value - 1].id) }
                    return true
                }
                if modifiers == .control {
                    if session.spaces.indices.contains(value - 1) {
                        selectSpace(session.spaces[value - 1].id)
                    }
                    return true
                }
            }
            if modifiers == [.command, .option] {
                switch event.keyCode {
                case 123:
                    adjacentSpace(-1)
                    return true
                case 124:
                    adjacentSpace(1)
                    return true
                case 125:
                    adjacentTab(1)
                    return true
                case 126:
                    adjacentTab(-1)
                    return true
                default: break
                }
            }
            if modifiers == [.command, .control], activeSplit != nil {
                if event.keyCode == 123 {
                    focusSplit(-1)
                    return true
                }
                if event.keyCode == 124 {
                    focusSplit(1)
                    return true
                }
            }
            if modifiers == [.command, .shift], activeSplit != nil {
                if event.keyCode == 123 {
                    moveSplitCard(-1)
                    return true
                }
                if event.keyCode == 124 {
                    moveSplitCard(1)
                    return true
                }
            }
        }
        if event.type == .keyDown, event.keyCode == 48, event.modifierFlags.contains(.control) {
            selectRecentTab(delta: event.modifierFlags.contains(.shift) ? -1 : 1)
            return true
        }
        if event.type == .flagsChanged, !event.modifierFlags.contains(.control), recentSwitcherPresented {
            commitRecentTab()
        }
        return false
    }
}
