import AppKit

/// The Dock icon's menu, as the core answers it: Crest's window commands,
/// then the Spaces a window can show, each drawn as the Space switcher draws
/// it and checked when the frontmost window shows it. macOS adds the window
/// list and its own items around it.
///
/// A command runs as the menu bar runs it, from the window the core names. A
/// Space shows in that window, which is never a private one, or opens a
/// window on itself when the core names none; a locked Space shows locked
/// there, where the person unlocks it as they would anywhere else.
@MainActor
final class BrowserMacDockMenu: NSObject {
    // MARK: - Types

    /// A command chosen from the menu, and the window it acts from.
    private struct CommandChoice {
        let command: DockMenuCommand
        let windowID: UUID?
    }

    /// A Space chosen from the menu, and the window it shows in.
    private struct SpaceChoice {
        let space: DockMenuSpace
        let windowID: UUID?
    }

    // MARK: - Variables

    private unowned let application: BrowserMacApplication
    private unowned let windows: BrowserMacWindows

    // MARK: - Initializers

    init(application: BrowserMacApplication, windows: BrowserMacWindows) {
        self.application = application
        self.windows = windows
    }

    // MARK: - Actions - Menu

    /// The menu the Dock shows now, or nil when the core cannot answer.
    func menu() -> NSMenu? {
        guard let content = try? application.browser.core.query(DockMenu(windowIDs: application.stackedWindowIDs))
        else {
            return nil
        }
        let menu = NSMenu()
        for command in content.commands {
            let item = NSMenuItem(
                title: String(localized: command.title), action: #selector(runCommand(_:)), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: command.command.symbol, accessibilityDescription: nil)
            item.representedObject = CommandChoice(command: command, windowID: content.windowID)
            item.target = self
            menu.addItem(item)
        }
        if !content.spaces.isEmpty { menu.addItem(.separator()) }
        for space in content.spaces {
            let item = NSMenuItem(title: space.name, action: #selector(showSpace(_:)), keyEquivalent: "")
            item.image = BrowserSpaceSymbolArtworkRenderer.shared.menuImage(for: BrowserSpaceIdentity(dockSpace: space))
            item.state = space.isShown ? .on : .off
            item.representedObject = SpaceChoice(space: space, windowID: content.windowID)
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    // MARK: - Actions - Choices

    @objc private func runCommand(_ item: NSMenuItem) {
        guard let choice = item.representedObject as? CommandChoice else { return }
        NSApp.activate()
        actions(from: choice.windowID).perform(choice.command.command)
    }

    @objc private func showSpace(_ item: NSMenuItem) {
        guard let choice = item.representedObject as? SpaceChoice else { return }
        NSApp.activate()
        if let windowID = choice.windowID, let model = application.windowCoordinator.existingModel(for: windowID) {
            actions(from: windowID).selectSpace(choice.space.spaceID)
            if let window = model.window {
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.makeKeyAndOrderFront(nil)
            }
            return
        }
        // No window can show the Space, so the person asked for one.
        let request = BrowserMacWindowRequest.normal(sourceWindowID: nil)
        guard let model = application.windowCoordinator.model(for: request) else { return }
        model.browser.selectSpace(choice.space.spaceID)
        windows.open(request, activation: .key)
    }

    /// The menu bar's commands as they run in the window `windowID`, or as
    /// they run with no window focused when it is nil.
    private func actions(from windowID: UUID?) -> BrowserCommandActions {
        if let windowID, let model = application.windowCoordinator.existingModel(for: windowID) {
            return BrowserCommandActions(
                browser: model.browser, pages: model.pages, chrome: model.chrome, windows: windows,
                spaceAccess: application.spaceAccess, targetWindowID: windowID)
        }
        return BrowserCommandActions(
            browser: application.browser, pages: application.pages, chrome: application.chrome, windows: windows,
            spaceAccess: application.spaceAccess)
    }
}
