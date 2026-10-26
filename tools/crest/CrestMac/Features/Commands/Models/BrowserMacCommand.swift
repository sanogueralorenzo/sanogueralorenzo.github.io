import AppKit
import SwiftUI

/// What one command does in the Mac shell: whether it can do it now, what the
/// menu bar calls it and whether it checks it when that follows the window,
/// and what it runs. Each command the core names has exactly one, which the
/// menu bar, its keys and the command palette all run. The core says what a
/// window's contents allow; a command here says what the page and its engine
/// can do.
@MainActor
struct BrowserMacCommand {
    // MARK: - Static Variables

    static let newWindow = BrowserMacCommand(
        .newWindow, withoutWindow: .always { $0.open(.normal(sourceWindowID: nil), activation: .key) },
        run: { $0.openNewWindow() })
    static let newBlankWindow = BrowserMacCommand(.newBlankWindow) { $0.openBlankWindow() }
    static let newTab = BrowserMacCommand(.newTab) { $0.openNewTab() }
    static let openLocation = BrowserMacCommand(.openLocation) { $0.openLocation() }
    static let openFile = BrowserMacCommand(
        .openFile, isAvailable: { $0.supportsEngineCapability(.localFiles) },
        run: { $0.openFile() })
    static let newQuickWindow = BrowserMacCommand(.newQuickWindow) { $0.openQuickWindow() }
    static let newPrivateWindow = BrowserMacCommand(
        .newPrivateWindow, withoutWindow: .always { $0.openPrivateWindow() },
        run: { $0.openPrivateWindow() })
    static let closeTabOrWindow = BrowserMacCommand(
        .closeTabOrWindow, withoutWindow: .closesShellWindow,
        run: { $0.closeTabOrWindow() })
    static let closeWindow = BrowserMacCommand(
        .closeWindow, withoutWindow: .closesShellWindow, run: { $0.closeKeyWindow() })
    static let back = BrowserMacCommand(
        .back, actsOnPage: true, isAvailable: { $0.commandPage?.live.canGoBack == true },
        run: { $0.commandPage?.goBack() })
    static let forward = BrowserMacCommand(
        .forward, actsOnPage: true, isAvailable: { $0.commandPage?.live.canGoForward == true },
        run: { $0.commandPage?.goForward() })
    static let reloadPage = BrowserMacCommand(.reloadPage, actsOnPage: true) { $0.reload(.standard) }
    static let stopLoading = BrowserMacCommand(
        .stopLoading, actsOnPage: true, isAvailable: { $0.commandPage?.live.isLoading == true },
        run: { $0.commandPage?.stopLoading() })
    static let reloadFromOrigin = BrowserMacCommand(.reloadFromOrigin, actsOnPage: true) { $0.reload(.fromOrigin) }
    static let toggleSelectedTabPinned = BrowserMacCommand(.toggleSelectedTabPinned) { $0.toggleSelectedTabPinned() }
    static let duplicateTab = BrowserMacCommand(.duplicateTab) { $0.duplicateSelectedTab() }
    static let reopenClosedTab = BrowserMacCommand(.reopenClosedTab) { $0.reopenClosedTab() }
    static let clearUnpinnedTabs = BrowserMacCommand(.clearUnpinnedTabs) { $0.cleanupCurrentTabs() }
    static let archiveTab = BrowserMacCommand(.archiveTab) { $0.archiveSelectedTab() }
    static let previousTab = BrowserMacCommand(.previousTab) { $0.selectPreviousTab() }
    static let nextTab = BrowserMacCommand(.nextTab) { $0.selectNextTab() }
    static let mostRecentTab = BrowserMacCommand(
        .mostRecentTab, recentTabDirection: .forward, run: { $0.selectMostRecentTab() })
    static let mostRecentTabBackward = BrowserMacCommand(
        .mostRecentTabBackward, recentTabDirection: .backward, run: { $0.selectLeastRecentTab() })
    static let splitWithNextTab = BrowserMacCommand(.splitWithNextTab) { $0.splitWithNextTab() }
    static let focusNextSplitCard = BrowserMacCommand(.focusNextSplitCard) { $0.focusAdjacentSplitCard(offset: 1) }
    static let focusPreviousSplitCard = BrowserMacCommand(.focusPreviousSplitCard) {
        $0.focusAdjacentSplitCard(offset: -1)
    }
    static let removeTabFromSplit = BrowserMacCommand(.removeTabFromSplit) { $0.removeSelectedTabFromSplit() }
    static let separateSplitTabs = BrowserMacCommand(.separateSplitTabs) { $0.separateSplitTabs() }
    static let moveSplitCardLeft = BrowserMacCommand(
        .moveSplitCardLeft, isAvailable: { $0.canMoveFocusedSplitCard(.left) },
        run: { $0.moveFocusedSplitCard(.left) })
    static let moveSplitCardRight = BrowserMacCommand(
        .moveSplitCardRight, isAvailable: { $0.canMoveFocusedSplitCard(.right) },
        run: { $0.moveFocusedSplitCard(.right) })
    static let previousSpace = BrowserMacCommand(.previousSpace) { $0.selectPreviousSpace() }
    static let nextSpace = BrowserMacCommand(.nextSpace) { $0.selectNextSpace() }
    static let toggleReaderMode = BrowserMacCommand(
        .toggleReaderMode, actsOnPage: true,
        isAvailable: { $0.supportsPageCapability(.reader) && $0.shownPage?.readerModeState.canToggle == true },
        title: { ($0.shownPage?.readerModeState ?? .unavailable).actionTitle },
        run: { $0.shownPage?.toggleReaderMode() })
    static let toggleContentBlocking = BrowserMacCommand(
        .toggleContentBlocking, actsOnPage: true, isAvailable: { $0.supportsEngineCapability(.contentBlocking) },
        title: { $0.contentBlockingActionTitle }, run: { $0.toggleContentBlocking() })
    static let findInPage = BrowserMacCommand(
        .findInPage, actsOnPage: true, isAvailable: { $0.canFind },
        run: { $0.presentFind() })
    static let findNext = BrowserMacCommand(
        .findNext, actsOnPage: true, isAvailable: { $0.canFindAgain }, waitsInPaletteUntilAvailable: true,
        run: { $0.commandPage?.findAgain(.forward) })
    static let findPrevious = BrowserMacCommand(
        .findPrevious, actsOnPage: true, isAvailable: { $0.canFindAgain }, waitsInPaletteUntilAvailable: true,
        run: { $0.commandPage?.findAgain(.backward) })
    static let zoomIn = BrowserMacCommand(.zoomIn, actsOnPage: true, isAvailable: { $0.canZoom }, run: { $0.zoomIn() })
    static let zoomOut = BrowserMacCommand(
        .zoomOut, actsOnPage: true, isAvailable: { $0.canZoom }, run: { $0.zoomOut() })
    static let actualSize = BrowserMacCommand(
        .actualSize, actsOnPage: true, isAvailable: { $0.canZoom }, run: { $0.resetZoom() })
    static let copyPageLink = BrowserMacCommand(
        .copyPageLink, actsOnPage: true, isAvailable: { $0.hasCommandPage },
        run: { $0.copyPageLink() })
    static let copyPageLinkAsMarkdown = BrowserMacCommand(
        .copyPageLinkAsMarkdown, actsOnPage: true, isAvailable: { $0.hasCommandPage },
        run: { $0.copyPageLinkAsMarkdown() })
    static let sharePage = BrowserMacCommand(
        .sharePage, actsOnPage: true, isAvailable: { $0.hasCommandPage },
        run: { $0.commandPage?.sharePage() })
    static let exportPDF = BrowserMacCommand(
        .exportPDF, actsOnPage: true, isAvailable: { $0.commandPageSupports(.pdf) },
        run: { $0.commandPage?.exportPDF() })
    static let saveWebArchive = BrowserMacCommand(
        .saveWebArchive, actsOnPage: true, isAvailable: { $0.commandPageSupports(.webArchive) },
        run: { $0.commandPage?.exportWebArchive() })
    static let printPage = BrowserMacCommand(
        .printPage, actsOnPage: true, isAvailable: { $0.commandPageSupports(.print) },
        run: { $0.commandPage?.printPage() })
    static let capturePage = BrowserMacCommand(
        .capturePage, actsOnPage: true, isAvailable: { $0.commandPageSupports(.viewportCapture) },
        isOn: { $0.commandPage?.isRegionCapturePresented == true },
        run: { $0.commandPage?.toggleRegionCapture() })
    static let clearSiteCookies = BrowserMacCommand(
        .clearSiteCookies, actsOnPage: true, isAvailable: { $0.commandPageShowsSite },
        run: { $0.clearCommandPageSiteData(.siteData) })
    static let clearSiteCache = BrowserMacCommand(
        .clearSiteCache, actsOnPage: true, isAvailable: { $0.commandPageShowsSite },
        run: { $0.clearCommandPageSiteData(.cache) })
    static let toggleSidebar = BrowserMacCommand(.toggleSidebar) { $0.toggleSidebar() }
    static let showHistory = BrowserMacCommand(.showHistory) { $0.chrome.toggleUtility(.history) }
    static let showArchive = BrowserMacCommand(.showArchive) { $0.chrome.toggleUtility(.archive) }
    static let showDownloads = BrowserMacCommand(
        .showDownloads, isAvailable: { $0.supportsEngineCapability(.downloads) },
        run: { $0.chrome.toggleUtility(.downloads) })
    static let showWebInspector = BrowserMacCommand(
        .showWebInspector, actsOnPage: true, isAvailable: { $0.supportsPageCapability(.inspector) },
        run: { _ = $0.shownPage?.showWebInspector() })
    static let toggleTranslationToolbar = BrowserMacCommand(
        .toggleTranslationToolbar, actsOnPage: true,
        isAvailable: { $0.supportsPageCapability(.translation) && $0.shownPage?.readerModeState.isActive != true },
        isOn: { $0.shownPage?.translation.showsToolbar == true },
        run: { actions in
            guard let page = actions.shownPage, !page.readerModeState.isActive else { return }
            page.translation.toggleToolbarVisibility()
        })
    static let toggleDeveloperToolbar = BrowserMacCommand(
        .toggleDeveloperToolbar, isAvailable: { $0.pages.hasActivePage },
        isOn: { $0.pages.activePage?.isDeveloperModeEnabled == true },
        run: { actions in
            guard let page = actions.pages.activePage else { return }
            page.setDeveloperToolbarVisible(!page.isDeveloperModeEnabled)
        })
    /// ⌘1–⌘9 and ⌃1–⌃9: the stop or Space the core says the number leads to now.
    static let selectNumbered = BrowserMacCommand(
        .selectNumbered, isAvailable: { actions, command in actions.numberedSelections[command] != nil },
        run: { actions, command in
            guard let selection = actions.numberedSelections[command] else { return }
            actions.select(selection)
        })

    /// Every command the Mac shell runs, one for each kind the core names.
    static let all = [
        newWindow, newBlankWindow, newTab, openLocation, openFile, newQuickWindow, newPrivateWindow, closeTabOrWindow,
        closeWindow,
        back, forward, reloadPage, stopLoading, reloadFromOrigin, toggleSelectedTabPinned, duplicateTab,
        reopenClosedTab,
        clearUnpinnedTabs, archiveTab, previousTab, nextTab, mostRecentTab, mostRecentTabBackward,
        splitWithNextTab, focusNextSplitCard,
        focusPreviousSplitCard, removeTabFromSplit, separateSplitTabs, moveSplitCardLeft, moveSplitCardRight,
        previousSpace, nextSpace,
        toggleReaderMode, toggleContentBlocking, findInPage, findNext, findPrevious, zoomIn, zoomOut, actualSize,
        copyPageLink,
        copyPageLinkAsMarkdown,
        sharePage, exportPDF, saveWebArchive, printPage, capturePage, clearSiteCookies, clearSiteCache,
        toggleSidebar, showHistory, showArchive, showDownloads,
        showWebInspector,
        toggleTranslationToolbar, toggleDeveloperToolbar, selectNumbered,
    ]

    // MARK: - Variables

    /// The kind of command this runs.
    let kind: ShortcutCommand.Kinds

    /// Whether the window can run the command now, as far as the page and its engine go.
    let isAvailable: @MainActor (BrowserCommandActions, ShortcutCommand) -> Bool

    /// What the menu bar calls the command now, or nil for its own title.
    let title: @MainActor (BrowserCommandActions) -> LocalizedStringResource?

    /// Whether what the command shows or hides is showing, or nil for a command
    /// the menu bar never checks.
    let isOn: @MainActor (BrowserCommandActions) -> Bool?

    /// Runs the command in a window.
    let run: @MainActor (BrowserCommandActions, ShortcutCommand) -> Void

    /// What the command does while no browser window is key, or nil for a
    /// command that needs one.
    let withoutWindow: BrowserMacWindowlessCommand?

    /// Whether the command acts on a page, which a Quick Window in front
    /// shows too, so a key Quick Window runs it on its own page.
    let actsOnPage: Bool

    /// Whether the palette lists the command only while it can run, for a
    /// command that means nothing until something else happens first, such
    /// as finding again before any search.
    let waitsInPaletteUntilAvailable: Bool

    /// Which way the command goes through the recent tabs when a held key
    /// begins it, or nil for a command that is not one of them. Chosen from
    /// the menu bar or the palette it jumps at once.
    let recentTabDirection: RecentTabSwitchDirection?

    // MARK: - Initializers

    private init(
        _ kind: ShortcutCommand.Kinds,
        actsOnPage: Bool = false,
        isAvailable: @escaping @MainActor (BrowserCommandActions) -> Bool = { _ in true },
        title: @escaping @MainActor (BrowserCommandActions) -> LocalizedStringResource? = { _ in nil },
        isOn: @escaping @MainActor (BrowserCommandActions) -> Bool? = { _ in nil },
        withoutWindow: BrowserMacWindowlessCommand? = nil,
        waitsInPaletteUntilAvailable: Bool = false,
        recentTabDirection: RecentTabSwitchDirection? = nil,
        run: @escaping @MainActor (BrowserCommandActions) -> Void
    ) {
        self.init(
            kind, actsOnPage: actsOnPage, isAvailable: { actions, _ in isAvailable(actions) }, title: title,
            isOn: isOn, withoutWindow: withoutWindow, waitsInPaletteUntilAvailable: waitsInPaletteUntilAvailable,
            recentTabDirection: recentTabDirection,
            run: { actions, _ in run(actions) })
    }

    private init(
        _ kind: ShortcutCommand.Kinds,
        actsOnPage: Bool = false,
        isAvailable: @escaping @MainActor (BrowserCommandActions, ShortcutCommand) -> Bool,
        title: @escaping @MainActor (BrowserCommandActions) -> LocalizedStringResource? = { _ in nil },
        isOn: @escaping @MainActor (BrowserCommandActions) -> Bool? = { _ in nil },
        withoutWindow: BrowserMacWindowlessCommand? = nil,
        waitsInPaletteUntilAvailable: Bool = false,
        recentTabDirection: RecentTabSwitchDirection? = nil,
        run: @escaping @MainActor (BrowserCommandActions, ShortcutCommand) -> Void
    ) {
        self.kind = kind
        self.actsOnPage = actsOnPage
        self.isAvailable = isAvailable
        self.title = title
        self.isOn = isOn
        self.withoutWindow = withoutWindow
        self.waitsInPaletteUntilAvailable = waitsInPaletteUntilAvailable
        self.recentTabDirection = recentTabDirection
        self.run = run
    }

    // MARK: - Actions - Lookup

    /// What `command` does in the Mac shell, or nil for a kind of command the
    /// shell does not run, which it then never offers.
    static func of(_ command: ShortcutCommand) -> BrowserMacCommand? {
        all.first { $0.kind == command.kind }
    }
}

/// What a command does while no browser window is key: a new window opens
/// from nothing, and a window the shell opened, such as a Quick Window or
/// setup, closes itself.
@MainActor
struct BrowserMacWindowlessCommand {
    // MARK: - Static Variables

    /// Closes the key window when it is one the shell opened.
    static let closesShellWindow = BrowserMacWindowlessCommand(
        isAvailable: { $0.isShellWindowKey }, run: { _ in NSApp.keyWindow?.performClose(nil) })

    // MARK: - Variables

    /// Whether the shell's windows can run it now.
    let isAvailable: @MainActor (BrowserMacWindows) -> Bool

    /// Runs it with the shell's windows.
    let run: @MainActor (BrowserMacWindows) -> Void

    // MARK: - Initializers

    /// A command that always runs with the shell's windows.
    static func always(_ run: @escaping @MainActor (BrowserMacWindows) -> Void) -> BrowserMacWindowlessCommand {
        BrowserMacWindowlessCommand(isAvailable: { _ in true }, run: run)
    }
}
