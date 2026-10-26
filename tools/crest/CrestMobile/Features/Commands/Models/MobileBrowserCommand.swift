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

    static let closeTabOrWindow = MobileBrowserCommand(
        .closeTabOrWindow, menuTitle: { _ in "Close Tab" }, isEnabled: { $0.canDismissSelectedTab },
        run: { $0.dismissSelectedTab() })
    static let back = MobileBrowserCommand(.back, isEnabled: { $0.canGoBack }, run: { $0.goBack() })
    static let forward = MobileBrowserCommand(.forward, isEnabled: { $0.canGoForward }, run: { $0.goForward() })
    static let reloadPage = MobileBrowserCommand(
        .reloadPage, isEnabled: { $0.hasActivePage }, run: { $0.reloadOrStop() })
    static let stopLoading = MobileBrowserCommand(.stopLoading, isEnabled: { $0.isLoading }, run: { $0.stopLoading() })
    static let reloadFromOrigin = MobileBrowserCommand(
        .reloadFromOrigin, isEnabled: { $0.hasActivePage }, run: { $0.reloadFromOrigin() })
    static let toggleSelectedTabPinned = MobileBrowserCommand(
        .toggleSelectedTabPinned, isEnabled: { $0.hasSelectedTab }, run: { $0.toggleSelectedTabPinned() })
    static let duplicateTab = MobileBrowserCommand(
        .duplicateTab, isEnabled: { $0.canDuplicateSelectedTab }, run: { $0.duplicateSelectedTab() })
    static let reopenClosedTab = MobileBrowserCommand(
        .reopenClosedTab, isEnabled: { $0.canReopenClosedTab }, run: { $0.reopenClosedTab() })
    static let clearUnpinnedTabs = MobileBrowserCommand(.clearUnpinnedTabs) { $0.cleanupCurrentTabs() }
    static let archiveTab = MobileBrowserCommand(
        .archiveTab, isEnabled: { $0.canArchiveSelectedTab }, run: { $0.archiveSelectedTab() })
    static let previousTab = MobileBrowserCommand(
        .previousTab, isEnabled: { $0.tabCount > 1 }, run: { $0.selectPreviousTab() })
    static let nextTab = MobileBrowserCommand(.nextTab, isEnabled: { $0.tabCount > 1 }, run: { $0.selectNextTab() })
    static let mostRecentTab = MobileBrowserCommand(
        .mostRecentTab, isEnabled: { $0.canJumpToRecentTab }, run: { $0.selectMostRecentTab() })
    static let mostRecentTabBackward = MobileBrowserCommand(
        .mostRecentTabBackward, isEnabled: { $0.canJumpToRecentTab }, run: { $0.selectLeastRecentTab() })
    static let splitWithNextTab = MobileBrowserCommand(
        .splitWithNextTab, isEnabled: { $0.canSplitWithNextTab }, run: { $0.splitWithNextTab() })
    static let focusNextSplitCard = MobileBrowserCommand(
        .focusNextSplitCard, isEnabled: { $0.isSelectedTabInSplit }, run: { $0.focusNextSplitCard() })
    static let focusPreviousSplitCard = MobileBrowserCommand(
        .focusPreviousSplitCard, isEnabled: { $0.isSelectedTabInSplit }, run: { $0.focusPreviousSplitCard() })
    static let removeTabFromSplit = MobileBrowserCommand(
        .removeTabFromSplit, isEnabled: { $0.isSelectedTabInSplit }, run: { $0.removeTabFromSplit() })
    static let separateSplitTabs = MobileBrowserCommand(
        .separateSplitTabs, isEnabled: { $0.isSelectedTabInSplit }, run: { $0.separateSplitTabs() })
    static let moveSplitCardLeft = MobileBrowserCommand(
        .moveSplitCardLeft, isEnabled: { $0.canMoveFocusedSplitCard(.left) }, run: { $0.moveFocusedSplitCard(.left) })
    static let moveSplitCardRight = MobileBrowserCommand(
        .moveSplitCardRight, isEnabled: { $0.canMoveFocusedSplitCard(.right) },
        run: { $0.moveFocusedSplitCard(.right) })
    static let previousSpace = MobileBrowserCommand(
        .previousSpace, isEnabled: { $0.spaceCount > 1 }, run: { $0.selectPreviousSpace() })
    static let nextSpace = MobileBrowserCommand(
        .nextSpace, isEnabled: { $0.spaceCount > 1 }, run: { $0.selectNextSpace() })
    static let toggleReaderMode = MobileBrowserCommand(
        .toggleReaderMode, menuTitle: { $0?.readerModeActionTitle ?? "Show Reader" },
        isEnabled: { $0.canToggleReaderMode }, run: { $0.toggleReaderMode() })
    static let toggleContentBlocking = MobileBrowserCommand(
        .toggleContentBlocking, menuTitle: { $0?.contentBlockingActionTitle ?? "Content Blocking" },
        isEnabled: { $0.hasActivePage }, run: { $0.beginTogglingContentBlocking() })
    static let findInPage = MobileBrowserCommand(
        .findInPage, isEnabled: { $0.hasActivePage }, run: { $0.presentFind() })
    static let zoomIn = MobileBrowserCommand(.zoomIn, isEnabled: { $0.hasActivePage }, run: { $0.zoomIn() })
    static let zoomOut = MobileBrowserCommand(.zoomOut, isEnabled: { $0.hasActivePage }, run: { $0.zoomOut() })
    static let actualSize = MobileBrowserCommand(.actualSize, isEnabled: { $0.hasActivePage }, run: { $0.resetZoom() })
    static let copyPageLink = MobileBrowserCommand(
        .copyPageLink, isEnabled: { $0.hasActivePage }, run: { $0.copyPageLink() })
    static let copyPageLinkAsMarkdown = MobileBrowserCommand(
        .copyPageLinkAsMarkdown, isEnabled: { $0.hasActivePage }, run: { $0.copyPageLinkAsMarkdown() })
    static let printPage = MobileBrowserCommand(.printPage, isEnabled: { $0.hasActivePage }, run: { $0.printPage() })
    static let clearSiteCookies = MobileBrowserCommand(
        .clearSiteCookies, isEnabled: { $0.showsSite }, run: { $0.beginClearingSiteData(.siteData) })
    static let clearSiteCache = MobileBrowserCommand(
        .clearSiteCache, isEnabled: { $0.showsSite }, run: { $0.beginClearingSiteData(.cache) })
    static let toggleSidebar = MobileBrowserCommand(.toggleSidebar) { $0.toggleSidebar() }
    static let toggleTranslationToolbar = MobileBrowserCommand(
        .toggleTranslationToolbar, isAvailable: { $0.canToggleTranslationToolbar },
        isEnabled: { $0.canToggleTranslationToolbar },
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
        reopenClosedTab, clearUnpinnedTabs, archiveTab, previousTab, nextTab, mostRecentTab, mostRecentTabBackward,
        splitWithNextTab, focusNextSplitCard,
        focusPreviousSplitCard, removeTabFromSplit, separateSplitTabs, moveSplitCardLeft, moveSplitCardRight,
        previousSpace,
        nextSpace, toggleReaderMode, toggleContentBlocking, findInPage, zoomIn, zoomOut, actualSize, copyPageLink,
        copyPageLinkAsMarkdown, printPage, clearSiteCookies, clearSiteCache, toggleSidebar, toggleTranslationToolbar,
        showHistory, showArchive,
        showDownloads,
    ]

    // MARK: - Variables

    /// The core's command this runs.
    let command: ShortcutCommand

    /// What the hardware-keyboard menu calls it in a window, when that is not
    /// the core's own title; the menu calls on it with no window as well.
    let menuTitle: @MainActor (MobileBrowserCommandContext?) -> LocalizedStringResource?

    /// Whether a window can run it now, beyond what the core allows, which
    /// decides whether the palette lists it.
    let isAvailable: @MainActor (MobileBrowserCommandContext) -> Bool

    /// Whether the hardware-keyboard menu enables it in a window now.
    let isEnabled: @MainActor (MobileBrowserCommandContext) -> Bool

    /// Runs it in a window.
    let run: @MainActor (MobileBrowserCommandContext) -> Void

    // MARK: - Initializers

    private init(
        _ command: ShortcutCommand,
        menuTitle: @escaping @MainActor (MobileBrowserCommandContext?) -> LocalizedStringResource? = { _ in nil },
        isAvailable: @escaping @MainActor (MobileBrowserCommandContext) -> Bool = { _ in true },
        isEnabled: @escaping @MainActor (MobileBrowserCommandContext) -> Bool = { _ in true },
        run: @escaping @MainActor (MobileBrowserCommandContext) -> Void
    ) {
        self.command = command
        self.menuTitle = menuTitle
        self.isAvailable = isAvailable
        self.isEnabled = isEnabled
        self.run = run
    }

    // MARK: - Actions - Lookup

    /// What `command` does on the platform, or nil for one it has no answer for.
    static func of(_ command: ShortcutCommand) -> MobileBrowserCommand? {
        all.first { $0.command == command }
    }
}
