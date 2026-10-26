import SwiftUI

struct MobileBrowserCommands: Commands {
    let shortcuts: BrowserShortcutStore
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.mobileBrowserCommandContext) private var context

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(
                "New Window",
                systemImage: ShortcutCommand.newWindow.symbol
            ) {
                openWindow(value: MobileWindowRequest())
            }
            .keyboardShortcut(shortcut(.newWindow))

            Button(
                "New Tab",
                systemImage: ShortcutCommand.newTab.symbol
            ) {
                context?.openNewTab()
            }
            .keyboardShortcut(shortcut(.newTab))
            .disabled(context == nil)

            Button(
                context?.isPrivateBrowsing == true
                    ? "Leave Private Browsing" : "Private Browsing",
                systemImage: ShortcutCommand.newPrivateWindow.symbol
            ) {
                context?.togglePrivateBrowsing()
            }
            .keyboardShortcut(shortcut(.newPrivateWindow))
            .disabled(context == nil)

            button(.closeTabOrWindow)
        }

        CommandMenu("Navigate") {
            Button(
                "Open Location",
                systemImage: ShortcutCommand.openLocation.symbol
            ) {
                context?.openLocation()
            }
            .keyboardShortcut(shortcut(.openLocation))
            .disabled(context == nil)

            Divider()

            // The arrow aliases are second chords for commands the table
            // already carries, and the store holds exactly one binding per
            // command. They stay literal on purpose: a hardware keyboard on
            // iPad expects ⌘←/→ for history the way Safari does, and rebinding
            // "Back" should not take that away.
            button(.back)
            alias(.back, "Back (Arrow)", .leftArrow, modifiers: .command)
            button(.forward)
            alias(.forward, "Forward (Arrow)", .rightArrow, modifiers: .command)
            button(.reloadPage)
            button(.stopLoading)
            button(.reloadFromOrigin)
        }

        CommandMenu("Tabs") {
            button(.toggleSelectedTabPinned)
            button(.duplicateTab)
            button(.reopenClosedTab)
            button(.clearUnpinnedTabs)
            button(.archiveTab)

            Divider()

            button(.previousTab)
            button(.nextTab)
            alias(.previousTab, "Previous Tab (Bracket)", "[", modifiers: [.command, .shift])
            alias(.nextTab, "Next Tab (Bracket)", "]", modifiers: [.command, .shift])
            button(.mostRecentTab)
            button(.mostRecentTabBackward)

            Divider()

            button(.splitWithNextTab)
            button(.focusNextSplitCard)
            button(.focusPreviousSplitCard)
            button(.moveSplitCardLeft)
            button(.moveSplitCardRight)
            button(.removeTabFromSplit)
            button(.separateSplitTabs)

            Divider()

            let tabSelections = numberedSelections
            ForEach(1...9, id: \.self) { number in
                let command = ShortcutCommand.selecting(.tab, number: number)
                Button("Select Tab \(number)", systemImage: "\(number).square") {
                    if let tabID = command.flatMap({ numberedSelections[$0]?.tabID }) {
                        context?.selectTab(tabID)
                    }
                }
                .keyboardShortcut(tabSelectionShortcut(number))
                .disabled(command.flatMap { tabSelections[$0] } == nil)
            }
        }

        CommandMenu("Spaces") {
            button(.previousSpace)
            button(.nextSpace)

            Divider()

            let spaceSelections = numberedSelections
            ForEach(1...9, id: \.self) { number in
                let command = ShortcutCommand.selecting(.space, number: number)
                Button("Select Space \(number)", systemImage: "\(number).square") {
                    if let selection = command.flatMap({ numberedSelections[$0] }) {
                        context?.selectSpace(selection.spaceID)
                    }
                }
                .keyboardShortcut(spaceSelectionShortcut(number))
                .disabled(command.flatMap { spaceSelections[$0] } == nil)
            }
        }

        CommandMenu("Page") {
            button(.toggleReaderMode)
            button(.toggleContentBlocking)

            Divider()

            button(.findInPage)

            Divider()

            button(.zoomIn)
            button(.zoomOut)
            button(.actualSize)

            Divider()

            button(.copyPageLink)
            button(.copyPageLinkAsMarkdown)
        }

        CommandGroup(replacing: .printItem) {
            button(.printPage)
        }

        CommandGroup(after: .sidebar) {
            Toggle(
                isOn: Binding(
                    get: { context?.isTranslationToolbarVisible == true },
                    set: { context?.setTranslationToolbarVisible($0) }
                )
            ) {
                Label(
                    "Show Translation Toolbar",
                    systemImage: ShortcutCommand.toggleTranslationToolbar.symbol)
            }
            .keyboardShortcut(shortcut(.toggleTranslationToolbar))
            .disabled(context?.canToggleTranslationToolbar != true)

            button(.toggleSidebar)
            button(.showHistory)
            button(.showArchive)
            button(.showDownloads)
        }
    }

    /// The menu's item for `command`: its title and symbol, the window's
    /// action from the platform's command table and the person's chord,
    /// enabled while the window can run it.
    @ViewBuilder
    private func button(_ command: ShortcutCommand) -> some View {
        if let action = MobileBrowserCommand.of(command) {
            Button(
                action.menuTitle(context) ?? command.menuTitle ?? command.title,
                systemImage: command.symbol
            ) {
                if let context { action.run(context) }
            }
            .keyboardShortcut(shortcut(command))
            .disabled(context.map(action.isEnabled) != true)
        }
    }

    /// A second chord for `command`, which runs and enables as the command's
    /// own item does.
    @ViewBuilder
    private func alias(
        _ command: ShortcutCommand, _ title: LocalizedStringResource, _ key: KeyEquivalent,
        modifiers: EventModifiers
    ) -> some View {
        if let action = MobileBrowserCommand.of(command) {
            Button(title, systemImage: command.symbol) {
                if let context { action.run(context) }
            }
            .keyboardShortcut(key, modifiers: modifiers)
            .disabled(context.map(action.isEnabled) != true)
        }
    }

    private func shortcut(
        _ command: ShortcutCommand
    ) -> KeyboardShortcut? {
        shortcuts.keyboardShortcut(for: command)
    }

    /// Where each numbered selection command leads right now, per the core.
    private var numberedSelections: [ShortcutCommand: NumberedSelection] {
        context?.numberedSelections ?? [:]
    }

    private func tabSelectionShortcut(_ number: Int) -> KeyboardShortcut? {
        ShortcutCommand.selecting(.tab, number: number).flatMap(shortcut)
    }

    private func spaceSelectionShortcut(_ number: Int) -> KeyboardShortcut? {
        ShortcutCommand.selecting(.space, number: number).flatMap(shortcut)
    }
}
