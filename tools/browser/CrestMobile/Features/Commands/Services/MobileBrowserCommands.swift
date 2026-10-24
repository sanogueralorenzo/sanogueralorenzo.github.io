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

            Button(
                "Close Tab",
                systemImage: ShortcutCommand.closeTabOrWindow.symbol
            ) {
                context?.dismissSelectedTab()
            }
            .keyboardShortcut(shortcut(.closeTabOrWindow))
            .disabled(context?.canDismissSelectedTab != true)
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

            Button(
                "Back",
                systemImage: ShortcutCommand.back.symbol
            ) {
                context?.goBack()
            }
            .keyboardShortcut(shortcut(.back))
            .disabled(context?.canGoBack != true)

            // The arrow and bracket aliases below are second chords for commands
            // the table already carries, and the store holds exactly one binding
            // per command. They stay literal on purpose: a hardware keyboard on
            // iPad expects ⌘←/→ for history the way Safari does, and rebinding
            // "Back" should not take that away.
            Button(
                "Back (Arrow)",
                systemImage: ShortcutCommand.back.symbol
            ) {
                context?.goBack()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(context?.canGoBack != true)

            Button(
                "Forward",
                systemImage: ShortcutCommand.forward.symbol
            ) {
                context?.goForward()
            }
            .keyboardShortcut(shortcut(.forward))
            .disabled(context?.canGoForward != true)

            Button(
                "Forward (Arrow)",
                systemImage: ShortcutCommand.forward.symbol
            ) {
                context?.goForward()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(context?.canGoForward != true)

            Button(
                "Reload Page",
                systemImage: ShortcutCommand.reloadPage.symbol
            ) {
                context?.reloadOrStop()
            }
            .keyboardShortcut(shortcut(.reloadPage))
            .disabled(context?.hasActivePage != true)

            Button(
                "Stop Loading",
                systemImage: ShortcutCommand.stopLoading.symbol
            ) {
                context?.stopLoading()
            }
            .keyboardShortcut(shortcut(.stopLoading))
            .disabled(context?.isLoading != true)

            Button(
                "Reload from Origin",
                systemImage: ShortcutCommand.reloadFromOrigin.symbol
            ) {
                context?.reloadFromOrigin()
            }
            .keyboardShortcut(shortcut(.reloadFromOrigin))
            .disabled(context?.hasActivePage != true)
        }

        CommandMenu("Tabs") {
            Button(
                "Pin or Unpin Tab",
                systemImage: ShortcutCommand.toggleSelectedTabPinned.symbol
            ) {
                context?.toggleSelectedTabPinned()
            }
            .keyboardShortcut(shortcut(.toggleSelectedTabPinned))
            .disabled(context?.hasSelectedTab != true)

            Button(
                "Duplicate Tab",
                systemImage: ShortcutCommand.duplicateTab.symbol
            ) {
                context?.duplicateSelectedTab()
            }
            .keyboardShortcut(shortcut(.duplicateTab))
            .disabled(context?.canDuplicateSelectedTab != true)

            Button(
                "Reopen Closed Tab",
                systemImage: ShortcutCommand.reopenClosedTab.symbol
            ) {
                context?.reopenClosedTab()
            }
            .keyboardShortcut(shortcut(.reopenClosedTab))
            .disabled(context?.canReopenClosedTab != true)

            Button(
                "Clear Unpinned Tabs",
                systemImage: ShortcutCommand.clearUnpinnedTabs.symbol
            ) {
                context?.cleanupCurrentTabs()
            }
            .keyboardShortcut(shortcut(.clearUnpinnedTabs))
            .disabled(context == nil)

            Button(
                "Archive Tab",
                systemImage: ShortcutCommand.archiveTab.symbol
            ) {
                context?.archiveSelectedTab()
            }
            .keyboardShortcut(shortcut(.archiveTab))
            .disabled(context?.canArchiveSelectedTab != true)

            Divider()

            Button(
                "Previous Tab",
                systemImage: ShortcutCommand.previousTab.symbol
            ) {
                context?.selectPreviousTab()
            }
            .keyboardShortcut(shortcut(.previousTab))
            .disabled((context?.tabCount ?? 0) < 2)

            Button(
                "Next Tab",
                systemImage: ShortcutCommand.nextTab.symbol
            ) {
                context?.selectNextTab()
            }
            .keyboardShortcut(shortcut(.nextTab))
            .disabled((context?.tabCount ?? 0) < 2)

            Button(
                "Previous Tab (Bracket)",
                systemImage: ShortcutCommand.previousTab.symbol
            ) {
                context?.selectPreviousTab()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled((context?.tabCount ?? 0) < 2)

            Button(
                "Next Tab (Bracket)",
                systemImage: ShortcutCommand.nextTab.symbol
            ) {
                context?.selectNextTab()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled((context?.tabCount ?? 0) < 2)

            Button(
                "Most Recent Tab",
                systemImage: ShortcutCommand.mostRecentTab.symbol
            ) {
                context?.selectMostRecentTab()
            }
            .keyboardShortcut(shortcut(.mostRecentTab))
            .disabled((context?.tabCount ?? 0) < 2)

            Divider()

            Button(
                "Split With Next Tab",
                systemImage: ShortcutCommand.splitWithNextTab.symbol
            ) {
                context?.splitWithNextTab()
            }
            .keyboardShortcut(shortcut(.splitWithNextTab))
            .disabled(context?.canSplitWithNextTab != true)

            Button(
                "Focus Next Split Card",
                systemImage: ShortcutCommand.focusNextSplitCard.symbol
            ) {
                context?.focusNextSplitCard()
            }
            .keyboardShortcut(shortcut(.focusNextSplitCard))
            .disabled(context?.isSelectedTabInSplit != true)

            Button(
                "Focus Previous Split Card",
                systemImage: ShortcutCommand.focusPreviousSplitCard.symbol
            ) {
                context?.focusPreviousSplitCard()
            }
            .keyboardShortcut(shortcut(.focusPreviousSplitCard))
            .disabled(context?.isSelectedTabInSplit != true)

            Button(
                "Move Split Card Left",
                systemImage: ShortcutCommand.moveSplitCardLeft.symbol
            ) {
                context?.moveFocusedSplitCard(.left)
            }
            .keyboardShortcut(shortcut(.moveSplitCardLeft))
            .disabled(context?.canMoveFocusedSplitCard(.left) != true)

            Button(
                "Move Split Card Right",
                systemImage: ShortcutCommand.moveSplitCardRight.symbol
            ) {
                context?.moveFocusedSplitCard(.right)
            }
            .keyboardShortcut(shortcut(.moveSplitCardRight))
            .disabled(context?.canMoveFocusedSplitCard(.right) != true)

            Button(
                "Remove Tab From Split",
                systemImage: ShortcutCommand.removeTabFromSplit.symbol
            ) {
                context?.removeTabFromSplit()
            }
            .keyboardShortcut(shortcut(.removeTabFromSplit))
            .disabled(context?.isSelectedTabInSplit != true)

            Button(
                "Separate All Tabs",
                systemImage: ShortcutCommand.separateSplitTabs.symbol
            ) {
                context?.separateSplitTabs()
            }
            .keyboardShortcut(shortcut(.separateSplitTabs))
            .disabled(context?.isSelectedTabInSplit != true)

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
            Button(
                "Previous Space",
                systemImage: ShortcutCommand.previousSpace.symbol
            ) {
                context?.selectPreviousSpace()
            }
            .keyboardShortcut(shortcut(.previousSpace))
            .disabled((context?.spaceCount ?? 0) < 2)

            Button(
                "Next Space",
                systemImage: ShortcutCommand.nextSpace.symbol
            ) {
                context?.selectNextSpace()
            }
            .keyboardShortcut(shortcut(.nextSpace))
            .disabled((context?.spaceCount ?? 0) < 2)

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
            Button(
                context?.readerModeActionTitle ?? "Show Reader",
                systemImage: ShortcutCommand.toggleReaderMode.symbol
            ) {
                context?.toggleReaderMode()
            }
            .keyboardShortcut(shortcut(.toggleReaderMode))
            .disabled(context?.canToggleReaderMode != true)

            Button(
                context?.contentBlockingActionTitle ?? "Content Blocking",
                systemImage: ShortcutCommand.toggleContentBlocking.symbol
            ) {
                Task { await context?.toggleContentBlocking() }
            }
            .keyboardShortcut(shortcut(.toggleContentBlocking))
            .disabled(context?.hasActivePage != true)

            Divider()

            Button(
                "Find in Page",
                systemImage: ShortcutCommand.findInPage.symbol
            ) {
                context?.presentFind()
            }
            .keyboardShortcut(shortcut(.findInPage))
            .disabled(context?.hasActivePage != true)

            Divider()

            Button(
                "Zoom In",
                systemImage: ShortcutCommand.zoomIn.symbol
            ) {
                context?.zoomIn()
            }
            .keyboardShortcut(shortcut(.zoomIn))
            .disabled(context?.hasActivePage != true)

            Button(
                "Zoom Out",
                systemImage: ShortcutCommand.zoomOut.symbol
            ) {
                context?.zoomOut()
            }
            .keyboardShortcut(shortcut(.zoomOut))
            .disabled(context?.hasActivePage != true)

            Button(
                "Actual Size",
                systemImage: ShortcutCommand.actualSize.symbol
            ) {
                context?.resetZoom()
            }
            .keyboardShortcut(shortcut(.actualSize))
            .disabled(context?.hasActivePage != true)

            Divider()

            Button(
                "Copy Page Link",
                systemImage: ShortcutCommand.copyPageLink.symbol
            ) {
                context?.copyPageLink()
            }
            .keyboardShortcut(shortcut(.copyPageLink))
            .disabled(context?.hasActivePage != true)

            Button(
                "Copy Page Link as Markdown",
                systemImage: ShortcutCommand.copyPageLinkAsMarkdown.symbol
            ) {
                context?.copyPageLinkAsMarkdown()
            }
            .keyboardShortcut(shortcut(.copyPageLinkAsMarkdown))
            .disabled(context?.hasActivePage != true)
        }

        CommandGroup(replacing: .printItem) {
            Button(
                "Print…",
                systemImage: ShortcutCommand.printPage.symbol
            ) {
                context?.printPage()
            }
            .keyboardShortcut(shortcut(.printPage))
            .disabled(context?.hasActivePage != true)
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

            Button(
                "Toggle Sidebar",
                systemImage: ShortcutCommand.toggleSidebar.symbol
            ) {
                context?.toggleSidebar()
            }
            .keyboardShortcut(shortcut(.toggleSidebar))
            .disabled(context == nil)

            Button(
                "Show History",
                systemImage: ShortcutCommand.showHistory.symbol
            ) {
                context?.presentHistory()
            }
            .keyboardShortcut(shortcut(.showHistory))
            .disabled(context == nil)

            Button(
                "Show Archive",
                systemImage: ShortcutCommand.showArchive.symbol
            ) {
                context?.presentArchive()
            }
            .keyboardShortcut(shortcut(.showArchive))
            .disabled(context == nil)

            Button(
                "Show Downloads",
                systemImage: ShortcutCommand.showDownloads.symbol
            ) {
                context?.presentDownloads()
            }
            .keyboardShortcut(shortcut(.showDownloads))
            .disabled(context == nil)
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
