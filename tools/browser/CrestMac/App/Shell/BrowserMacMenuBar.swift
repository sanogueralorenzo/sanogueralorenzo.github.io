import AppKit
import Observation

/// The application's menu bar: Crest's commands in AppKit menus, laid out as
/// the core's `ShortcutMenu`s lay them out, which act on the key browser
/// window, around AppKit's own application, Edit, Window and Help menus. A
/// page's context menu stays its engine's own.
///
/// The menus show the commands the device offers, as the read model says: a
/// command whose feature neither the default engine nor an engine a page is
/// open on supports is hidden, and it appears once such a page opens. The page
/// a command acts on enables it through its own engine.
@MainActor
final class BrowserMacMenuBar: NSObject, NSMenuDelegate, NSMenuItemValidation {
    // MARK: - Variables

    private unowned let shell: BrowserMacShell
    private let shortcuts: BrowserShortcutStore
    private let state: CoreState
    /// Each command's item, whose chord and visibility follow the read model,
    /// with the title it was made with.
    private var commandItems: [(command: ShortcutCommand, item: NSMenuItem, title: String)] = []
    /// Each application action's item, whose visibility follows the read
    /// model.
    private var actionItems: [(action: BrowserMacApplicationAction, item: NSMenuItem)] = []
    /// The menus that hold commands, whose separators follow what is offered.
    private var commandMenus: [NSMenu] = []
    /// The Page menu, which ends with a row for each engine the shown page
    /// can move to.
    private weak var pageMenu: NSMenu?
    /// The Page menu's engine rows as last built, with their separator.
    private var engineMoveItems: [NSMenuItem] = []

    // MARK: - Initializers

    init(shell: BrowserMacShell, shortcuts: BrowserShortcutStore, state: CoreState) {
        self.shell = shell
        self.shortcuts = shortcuts
        self.state = state
    }

    // MARK: - Actions - Installation

    /// Makes these menus the application's: the application menu, then the
    /// core's menus of Crest's commands in the core's order, with AppKit's
    /// Edit menu after File, then Window and Help. AppKit's own items join the
    /// core's menus where the Mac keeps them: whole-page translation leads
    /// Page, and full screen ends View.
    func install() {
        let bar = BrowserMacMainMenu()
        bar.shell = shell
        applicationMenu(in: bar)
        for menu in ShortcutMenu.all {
            let items = submenu(String(localized: menu.title), in: bar)
            if menu == .page {
                applicationItem(.translatePage, in: items)
                pageMenu = items
            }
            commands(menu.groups, in: items)
            if menu == .view {
                items.addItem(.separator())
                standard(
                    String(localized: "Enter Full Screen"), #selector(NSWindow.toggleFullScreen(_:)), key: "f",
                    modifiers: [.command, .control], in: items)
            }
            if menu == .file { editMenu(in: bar) }
        }
        windowMenu(in: bar)
        let help = submenu(String(localized: "Help"), in: bar)
        applicationItem(.gettingStarted, in: help)
        NSApp.helpMenu = help
        NSApp.mainMenu = bar
        observeReadModel()
    }

    private func applicationMenu(in bar: NSMenu) {
        let app = submenu(ProductIdentity.name, in: bar)
        applicationItem(.about, in: app)
        applicationItem(.updates, in: app)
        app.addItem(.separator())
        applicationItem(.settings, in: app)
        applicationItem(.stopAllAgents, in: app)
        NSApp.servicesMenu = submenu(String(localized: "Services"), in: app)
        app.addItem(.separator())
        standard(String(localized: "Hide Crest"), #selector(NSApplication.hide(_:)), key: "h", in: app, target: NSApp)
        standard(
            String(localized: "Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), key: "h",
            modifiers: [.command, .option], in: app, target: NSApp)
        standard(
            String(localized: "Show All"), #selector(NSApplication.unhideAllApplications(_:)), in: app, target: NSApp)
        app.addItem(.separator())
        standard(
            String(localized: "Quit Crest"), #selector(NSApplication.terminate(_:)), key: "q", in: app, target: NSApp)
    }

    private func editMenu(in bar: NSMenu) {
        let edit = submenu(String(localized: "Edit"), in: bar)
        standard(String(localized: "Undo"), Selector(("undo:")), key: "z", in: edit)
        standard(String(localized: "Redo"), Selector(("redo:")), key: "z", modifiers: [.command, .shift], in: edit)
        edit.addItem(.separator())
        standard(String(localized: "Cut"), #selector(NSText.cut(_:)), key: "x", in: edit)
        standard(String(localized: "Copy"), #selector(NSText.copy(_:)), key: "c", in: edit)
        standard(String(localized: "Paste"), #selector(NSText.paste(_:)), key: "v", in: edit)
        let pasteAsPlainText = NSMenuItem(
            title: String(localized: "Paste and Match Style"), action: #selector(pasteAsPlainText(_:)),
            keyEquivalent: "v")
        pasteAsPlainText.target = self
        pasteAsPlainText.keyEquivalentModifierMask = [.command, .option, .shift]
        edit.addItem(pasteAsPlainText)
        standard(String(localized: "Delete"), #selector(NSText.delete(_:)), in: edit)
        standard(String(localized: "Select All"), #selector(NSText.selectAll(_:)), key: "a", in: edit)
        edit.addItem(.separator())
        textItems(in: edit)
    }

    private func windowMenu(in bar: NSMenu) {
        let window = submenu(String(localized: "Window"), in: bar)
        standard(String(localized: "Minimize"), #selector(NSWindow.performMiniaturize(_:)), key: "m", in: window)
        standard(String(localized: "Zoom"), #selector(NSWindow.performZoom(_:)), in: window)
        window.addItem(.separator())
        standard(
            String(localized: "Bring All to Front"), #selector(NSApplication.arrangeInFront(_:)), in: window,
            target: NSApp)
        NSApp.windowsMenu = window
    }

    // MARK: - Actions - Menus

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === pageMenu { refreshEngineMoves() }
        refreshBindings()
        refreshOffers()
        refreshTitles(in: menu)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if let command = item.representedObject as? ShortcutCommand {
            item.state = shell.actions(for: command)?.isOn(command) == true ? .on : .off
            return shell.canPerform(command)
        }
        if let action = item.representedObject as? BrowserMacApplicationAction {
            return action.isEnabled(in: shell)
        }
        if item.action == #selector(pasteAsPlainText(_:)) {
            return BrowserPlainTextPaste(for: focusedResponder, validating: item) != nil
        }
        return true
    }

    @objc private func runCommand(_ item: NSMenuItem) {
        guard let command = item.representedObject as? ShortcutCommand else { return }
        shell.perform(command)
    }

    /// Pastes as plain text into the focused field or page, whichever selector
    /// that responder takes.
    @objc private func pasteAsPlainText(_ item: NSMenuItem) {
        BrowserPlainTextPaste(for: focusedResponder)?.perform()
    }

    private var focusedResponder: NSResponder? {
        (NSApp.keyWindow ?? NSApp.mainWindow)?.firstResponder
    }

    @objc private func runApplicationAction(_ item: NSMenuItem) {
        guard let action = item.representedObject as? BrowserMacApplicationAction else { return }
        action.perform(in: shell)
    }

    @objc private func movePage(_ item: NSMenuItem) {
        guard let engine = item.representedObject as? EngineKind else { return }
        shell.pageActions?.movePage(to: engine)
    }

    // MARK: - Actions - Read model

    /// Follows each command's chord and whether the device offers it.
    private func observeReadModel() {
        withObservationTracking {
            refreshBindings()
            refreshOffers()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeReadModel() }
        }
    }

    private func refreshBindings() {
        for (command, item, _) in commandItems {
            let shortcut = shortcuts.shortcut(for: command)
            item.keyEquivalent = shortcut.map { String($0.key.keyEquivalent.character) } ?? ""
            item.keyEquivalentModifierMask = shortcut?.modifiers.appKitModifierFlags ?? []
        }
    }

    /// Ends the Page menu with a row for each registered engine the shown
    /// page is not on. Moving depends only on the engine being registered,
    /// so the rows are there before any page has opened on it.
    private func refreshEngineMoves() {
        guard let pageMenu else { return }
        for item in engineMoveItems { pageMenu.removeItem(item) }
        engineMoveItems = []
        let engines = shell.pageActions?.pageEngineMoves ?? []
        guard !engines.isEmpty else { return }
        engineMoveItems.append(.separator())
        for engine in engines {
            let item = NSMenuItem(
                title: String(localized: "Open Page in \(String(localized: engine.title))"),
                action: #selector(movePage(_:)), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "arrow.triangle.swap", accessibilityDescription: nil)
            item.target = self
            item.representedObject = engine
            engineMoveItems.append(item)
        }
        for item in engineMoveItems { pageMenu.addItem(item) }
    }

    /// Names each command in `menu` as the key window calls it now, such as
    /// Reader's Show or Hide, and otherwise as its item was made.
    private func refreshTitles(in menu: NSMenu) {
        for (command, item, title) in commandItems where item.menu === menu {
            item.title = shell.actions(for: command)?.menuTitle(of: command).map { String(localized: $0) } ?? title
        }
    }

    /// Hides each command the device does not offer, which also takes its
    /// chord out of key equivalent matching, then each separator left leading
    /// a menu, following another or ending it.
    private func refreshOffers() {
        for (command, item, _) in commandItems {
            item.isHidden = !command.isOffered(in: state)
        }
        for (action, item) in actionItems {
            item.isHidden = !action.isOffered(in: state)
        }
        for menu in commandMenus {
            var lastShown: NSMenuItem?
            for item in menu.items {
                if item.isSeparatorItem { item.isHidden = lastShown?.isSeparatorItem ?? true }
                if !item.isHidden { lastShown = item }
            }
            if let lastShown, lastShown.isSeparatorItem { lastShown.isHidden = true }
        }
    }

    // MARK: - Actions - Items

    /// Adds an item for each command of `groups`, with a separator between
    /// one group and the next.
    private func commands(_ groups: [[ShortcutCommand]], in menu: NSMenu) {
        for (index, group) in groups.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for command in group { self.command(command, in: menu) }
        }
    }

    /// Adds an item for `command`, named `title` or as the command names
    /// itself in menus.
    private func command(_ command: ShortcutCommand, titled title: String? = nil, in menu: NSMenu) {
        if !commandMenus.contains(where: { $0 === menu }) { commandMenus.append(menu) }
        let title = title ?? String(localized: command.menuTitle ?? command.title)
        let item = NSMenuItem(title: title, action: #selector(runCommand(_:)), keyEquivalent: "")
        item.image = NSImage(systemSymbolName: command.symbol, accessibilityDescription: nil)
        item.target = self
        item.representedObject = command
        menu.addItem(item)
        commandItems.append((command, item, title))
    }

    private func applicationItem(_ action: BrowserMacApplicationAction, in menu: NSMenu) {
        let item = NSMenuItem(
            title: String(localized: action.title), action: #selector(runApplicationAction(_:)),
            keyEquivalent: action.keyEquivalent)
        item.image = action.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        item.target = self
        item.representedObject = action
        menu.addItem(item)
        actionItems.append((action, item))
    }

    /// The Edit menu's text submenus, which AppKit's responder chain answers
    /// for the field or page that has focus. Find and finding again use Crest's
    /// own find bar; the rest act on a text view's own find.
    private func textItems(in edit: NSMenu) {
        let find = submenu(String(localized: "Find"), in: edit)
        command(.findInPage, titled: String(localized: "Find…"), in: find)
        command(.findNext, in: find)
        command(.findPrevious, in: find)
        // Command-E archives a tab in Crest, so the selection has no chord.
        textFinder(String(localized: "Use Selection for Find"), .setSearchString, in: find)
        standard(
            String(localized: "Jump to Selection"), #selector(NSResponder.centerSelectionInVisibleArea(_:)), key: "j",
            in: find)

        let spelling = submenu(String(localized: "Spelling and Grammar"), in: edit)
        standard(
            String(localized: "Show Spelling and Grammar"), #selector(NSText.showGuessPanel(_:)), key: ":",
            in: spelling)
        standard(String(localized: "Check Document Now"), #selector(NSText.checkSpelling(_:)), key: ";", in: spelling)
        spelling.addItem(.separator())
        standard(
            String(localized: "Check Spelling While Typing"), #selector(NSTextView.toggleContinuousSpellChecking(_:)),
            in: spelling)
        standard(
            String(localized: "Check Grammar With Spelling"), #selector(NSTextView.toggleGrammarChecking(_:)),
            in: spelling)
        standard(
            String(localized: "Correct Spelling Automatically"),
            #selector(NSTextView.toggleAutomaticSpellingCorrection(_:)), in: spelling)

        let substitutions = submenu(String(localized: "Substitutions"), in: edit)
        standard(
            String(localized: "Show Substitutions"), #selector(NSTextView.orderFrontSubstitutionsPanel(_:)),
            in: substitutions)
        substitutions.addItem(.separator())
        standard(
            String(localized: "Smart Copy/Paste"), #selector(NSTextView.toggleSmartInsertDelete(_:)), in: substitutions)
        standard(
            String(localized: "Smart Quotes"), #selector(NSTextView.toggleAutomaticQuoteSubstitution(_:)),
            in: substitutions)
        standard(
            String(localized: "Smart Dashes"), #selector(NSTextView.toggleAutomaticDashSubstitution(_:)),
            in: substitutions)
        standard(
            String(localized: "Smart Links"), #selector(NSTextView.toggleAutomaticLinkDetection(_:)), in: substitutions)
        standard(
            String(localized: "Data Detectors"), #selector(NSTextView.toggleAutomaticDataDetection(_:)),
            in: substitutions)
        standard(
            String(localized: "Text Replacement"), #selector(NSTextView.toggleAutomaticTextReplacement(_:)),
            in: substitutions)

        let transformations = submenu(String(localized: "Transformations"), in: edit)
        standard(String(localized: "Make Upper Case"), #selector(NSResponder.uppercaseWord(_:)), in: transformations)
        standard(String(localized: "Make Lower Case"), #selector(NSResponder.lowercaseWord(_:)), in: transformations)
        standard(String(localized: "Capitalize"), #selector(NSResponder.capitalizeWord(_:)), in: transformations)

        let speech = submenu(String(localized: "Speech"), in: edit)
        standard(String(localized: "Start Speaking"), #selector(NSTextView.startSpeaking(_:)), in: speech)
        standard(String(localized: "Stop Speaking"), #selector(NSTextView.stopSpeaking(_:)), in: speech)
    }

    /// Adds an item that asks the focused text view's own find for `action`.
    private func textFinder(
        _ title: String, _ action: NSTextFinder.Action, key: String = "", modifiers: NSEvent.ModifierFlags = .command,
        in menu: NSMenu
    ) {
        standard(title, #selector(NSResponder.performTextFinderAction(_:)), key: key, modifiers: modifiers, in: menu)
        menu.items.last?.tag = action.rawValue
    }

    private func submenu(_ title: String, in parent: NSMenu) -> NSMenu {
        let menu = NSMenu(title: title)
        menu.delegate = self
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        parent.addItem(item)
        return menu
    }

    /// Adds an item AppKit's responder chain answers, or `target` when given.
    private func standard(
        _ title: String, _ action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = .command,
        in menu: NSMenu, target: AnyObject? = nil
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        item.keyEquivalentModifierMask = modifiers
        menu.addItem(item)
    }
}
