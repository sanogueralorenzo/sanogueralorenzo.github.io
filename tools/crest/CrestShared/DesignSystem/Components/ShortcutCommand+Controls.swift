import SwiftUI

extension Label where Title == Text, Icon == Image {
    /// One of the core's commands as every menu names and draws it: the menu
    /// bar, the iPad menu, the palette and the menus that offer it beside them.
    init(_ command: ShortcutCommand) {
        self.init {
            Text(command.menuTitle ?? command.title)
        } icon: {
            Image(systemName: command.symbol)
        }
    }
}

extension Button where Label == SwiftUI.Label<Text, Image> {
    /// A button that runs `action` for one of the core's commands, titled and
    /// drawn as the core names it.
    init(_ command: ShortcutCommand, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(role: role, action: action) {
            SwiftUI.Label(command)
        }
    }
}
