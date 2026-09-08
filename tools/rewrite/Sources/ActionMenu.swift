import AppKit

@MainActor
final class ActionMenu: NSObject {
    var onChoose: ((EditAction) -> Void)?
    let menu = NSMenu()
    override init() {
        super.init()
        menu.autoenablesItems = false
        for (index, action) in EditAction.allCases.enumerated() {
            let item = NSMenuItem(title: action.rawValue, action: #selector(choose(_:)), keyEquivalent: String(index + 1))
            item.keyEquivalentModifierMask = .option
            item.target = self; item.tag = index; menu.addItem(item)
        }
    }
    @objc private func choose(_ sender: NSMenuItem) { onChoose?(EditAction.allCases[sender.tag]) }
}
