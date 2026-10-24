import SwiftUI
import UIKit

/// What one command does on iPhone and iPad, from the palette or a hardware
/// keyboard: whether it can run now and what it runs. A command this list
/// leaves out has no answer on the platform, such as another kind of window,
/// the Web Inspector or the share and export sheets, and the palette never
/// offers it.
@MainActor
struct MobileBrowserCommand {
    // MARK: - Static Variables

    static let closeTabOrWindow = MobileBrowserCommand(.closeTabOrWindow) { $0.dismissSelectedTab() }
    static let back = MobileBrowserCommand(.back) { $0.goBack() }
    static let forward = MobileBrowserCommand(.forward) { $0.goForward() }
    static let reloadPage = MobileBrowserCommand(.reloadPage) { $0.reloadOrStop() }
    static let stopLoading = MobileBrowserCommand(.stopLoading) { $0.stopLoading() }
    static let reloadFromOrigin = MobileBrowserCommand(.reloadFromOrigin) { $0.reloadFromOrigin() }
    static let toggleSelectedTabPinned = MobileBrowserCommand(.toggleSelectedTabPinned) { $0.toggleSelectedTabPinned() }
    static let duplicateTab = MobileBrowserCommand(.duplicateTab) { $0.duplicateSelectedTab() }
    static let reopenClosedTab = MobileBrowserCommand(.reopenClosedTab) { $0.reopenClosedTab() }
    static let clearUnpinnedTabs = MobileBrowserCommand(.clearUnpinnedTabs) { $0.cleanupCurrentTabs() }
    static let archiveTab = MobileBrowserCommand(.archiveTab) { $0.archiveSelectedTab() }
    static let previousTab = MobileBrowserCommand(.previousTab) { $0.selectPreviousTab() }
    static let nextTab = MobileBrowserCommand(.nextTab) { $0.selectNextTab() }
    static let mostRecentTab = MobileBrowserCommand(.mostRecentTab) { $0.selectMostRecentTab() }
    static let splitWithNextTab = MobileBrowserCommand(.splitWithNextTab) { $0.splitWithNextTab() }
    static let focusNextSplitCard = MobileBrowserCommand(.focusNextSplitCard) { $0.focusNextSplitCard() }
    static let focusPreviousSplitCard = MobileBrowserCommand(.focusPreviousSplitCard) { $0.focusPreviousSplitCard() }
    static let removeTabFromSplit = MobileBrowserCommand(.removeTabFromSplit) { $0.removeTabFromSplit() }
    static let separateSplitTabs = MobileBrowserCommand(.separateSplitTabs) { $0.separateSplitTabs() }
    static let moveSplitCardLeft = MobileBrowserCommand(.moveSplitCardLeft) { $0.moveFocusedSplitCard(.left) }
    static let moveSplitCardRight = MobileBrowserCommand(.moveSplitCardRight) { $0.moveFocusedSplitCard(.right) }
    static let previousSpace = MobileBrowserCommand(.previousSpace) { $0.selectPreviousSpace() }
    static let nextSpace = MobileBrowserCommand(.nextSpace) { $0.selectNextSpace() }
    static let toggleReaderMode = MobileBrowserCommand(.toggleReaderMode) { $0.toggleReaderMode() }
    static let toggleContentBlocking = MobileBrowserCommand(.toggleContentBlocking) {
        $0.beginTogglingContentBlocking()
    }
    static let findInPage = MobileBrowserCommand(.findInPage) { $0.presentFind() }
    static let zoomIn = MobileBrowserCommand(.zoomIn) { $0.zoomIn() }
    static let zoomOut = MobileBrowserCommand(.zoomOut) { $0.zoomOut() }
    static let actualSize = MobileBrowserCommand(.actualSize) { $0.resetZoom() }
    static let copyPageLink = MobileBrowserCommand(.copyPageLink) { $0.copyPageLink() }
    static let copyPageLinkAsMarkdown = MobileBrowserCommand(.copyPageLinkAsMarkdown) { $0.copyPageLinkAsMarkdown() }
    static let printPage = MobileBrowserCommand(.printPage) { $0.printPage() }
    static let toggleSidebar = MobileBrowserCommand(.toggleSidebar) { $0.toggleSidebar() }
    static let toggleTranslationToolbar = MobileBrowserCommand(
        .toggleTranslationToolbar, isAvailable: { $0.canToggleTranslationToolbar },
        run: { context in
            context.setTranslationToolbarVisible(!context.isTranslationToolbarVisible)
        })
    static let showHistory = MobileBrowserCommand(.showHistory) { $0.presentHistory() }
    static let showArchive = MobileBrowserCommand(.showArchive) { $0.presentArchive() }
    static let showDownloads = MobileBrowserCommand(.showDownloads) { $0.presentDownloads() }

    /// The commands the platform runs, in the order the palette offers them.
    static let all = [
        closeTabOrWindow, back, forward, reloadPage, stopLoading, reloadFromOrigin, toggleSelectedTabPinned,
        duplicateTab,
        reopenClosedTab, clearUnpinnedTabs, archiveTab, previousTab, nextTab, mostRecentTab, splitWithNextTab,
        focusNextSplitCard,
        focusPreviousSplitCard, removeTabFromSplit, separateSplitTabs, moveSplitCardLeft, moveSplitCardRight,
        previousSpace,
        nextSpace, toggleReaderMode, toggleContentBlocking, findInPage, zoomIn, zoomOut, actualSize, copyPageLink,
        copyPageLinkAsMarkdown, printPage, toggleSidebar, toggleTranslationToolbar, showHistory, showArchive,
        showDownloads,
    ]

    // MARK: - Variables

    /// The core's command this runs.
    let command: ShortcutCommand

    /// Whether a window can run it now, beyond what the core allows.
    let isAvailable: @MainActor (MobileBrowserCommandContext) -> Bool

    /// Runs it in a window.
    let run: @MainActor (MobileBrowserCommandContext) -> Void

    // MARK: - Initializers

    /// A command a window can run whenever the core allows it.
    private init(_ command: ShortcutCommand, run: @escaping @MainActor (MobileBrowserCommandContext) -> Void) {
        self.init(command, isAvailable: { _ in true }, run: run)
    }

    private init(
        _ command: ShortcutCommand,
        isAvailable: @escaping @MainActor (MobileBrowserCommandContext) -> Bool,
        run: @escaping @MainActor (MobileBrowserCommandContext) -> Void
    ) {
        self.command = command
        self.isAvailable = isAvailable
        self.run = run
    }

    // MARK: - Actions - Lookup

    /// What `command` does on the platform, or nil for one it has no answer for.
    static func of(_ command: ShortcutCommand) -> MobileBrowserCommand? {
        all.first { $0.command == command }
    }
}
