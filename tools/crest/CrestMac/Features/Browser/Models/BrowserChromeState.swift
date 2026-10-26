import Observation
import SwiftUI

@Observable
@MainActor
final class BrowserChromeState {
    // MARK: - Variables

    let utilityPresentation: BrowserUtilityPresentationState
    var columnVisibility: NavigationSplitViewVisibility {
        get { observed(\.columnVisibilityStorage, as: \.columnVisibility) }
        set { publish(newValue, into: \.columnVisibilityStorage, as: \.columnVisibility) }
    }
    @ObservationIgnored private var columnVisibilityStorage: NavigationSplitViewVisibility
    /// Whether the undocked sidebar is floating over the page, as it does while
    /// the pointer rests at the window's edge.
    var isFloatingSidebarPresented: Bool {
        get { observed(\.isFloatingSidebarPresentedStorage, as: \.isFloatingSidebarPresented) }
        set { publish(newValue, into: \.isFloatingSidebarPresentedStorage, as: \.isFloatingSidebarPresented) }
    }
    @ObservationIgnored private var isFloatingSidebarPresentedStorage = false
    /// Whether a page shows alone in full screen with the sidebar hover area
    /// still live, where a docked sidebar gives way to the edge reveal.
    var revealsSidebarOverFullscreenPage: Bool {
        get { observed(\.revealsSidebarOverFullscreenPageStorage, as: \.revealsSidebarOverFullscreenPage) }
        set {
            publish(newValue, into: \.revealsSidebarOverFullscreenPageStorage, as: \.revealsSidebarOverFullscreenPage)
        }
    }
    @ObservationIgnored private var revealsSidebarOverFullscreenPageStorage = false
    private(set) var commandPaletteMode: BrowserCommandPaletteMode? {
        get { observed(\.commandPaletteModeStorage, as: \.commandPaletteMode) }
        set { publish(newValue, into: \.commandPaletteModeStorage, as: \.commandPaletteMode) }
    }
    @ObservationIgnored private var commandPaletteModeStorage: BrowserCommandPaletteMode?
    private(set) var addressFocusRequest = 0
    private(set) var startPageFocusRequest = 0
    private(set) var notice: BrowserNotice?
    private(set) var noticeRevision: Int {
        get { observed(\.noticeRevisionStorage, as: \.noticeRevision) }
        set { publish(newValue, into: \.noticeRevisionStorage, as: \.noticeRevision) }
    }
    @ObservationIgnored private var noticeRevisionStorage = 0
    /// The recent tabs a held Most Recent Tab shortcut shows over the window,
    /// or nil while none shows.
    var recentTabs: RecentTabSwitcherModel? {
        get { observed(\.recentTabsStorage, as: \.recentTabs) }
        set {
            guard recentTabsStorage !== newValue else { return }
            recentTabsStorage = newValue
            withMutation(keyPath: \.recentTabs) {}
        }
    }
    @ObservationIgnored private var recentTabsStorage: RecentTabSwitcherModel?

    var isCommandPalettePresented: Bool {
        commandPaletteMode != nil
    }

    // MARK: - Initializers

    init(
        sidebarIsPresented: Bool = true,
        utilityPresentation: BrowserUtilityPresentationState =
            BrowserUtilityPresentationState()
    ) {
        columnVisibilityStorage = sidebarIsPresented ? .all : .detailOnly
        self.utilityPresentation = utilityPresentation
    }

    // MARK: - Actions - Sidebar

    /// Hiding cancels utility presentation and pending input before an asynchronous view update can mount it.
    func hideSidebar() {
        utilityPresentation.dismiss()
        columnVisibility = .detailOnly
    }

    func showSidebar() {
        columnVisibility = .all
    }

    /// Brings `surface` up in the sidebar. Every route to History, Archive and
    /// Downloads comes through here, so none can open its list in a sidebar no
    /// one can see: a hidden sidebar docks first, and one floating over the
    /// page keeps floating.
    func presentUtility(_ surface: BrowserUtilitySurface) {
        if columnVisibility == .detailOnly, !isFloatingSidebarPresented {
            showSidebar()
        }
        utilityPresentation.present(surface)
    }

    /// Utility shortcuts preserve the docked preference and toggle a floating sidebar when hidden.
    func toggleUtility(_ surface: BrowserUtilitySurface) {
        if utilityPresentation.surface == surface,
            columnVisibility != .detailOnly || isFloatingSidebarPresented
        {
            utilityPresentation.dismiss(surface)
            if columnVisibility == .detailOnly {
                isFloatingSidebarPresented = false
            }
        } else {
            if columnVisibility == .detailOnly {
                isFloatingSidebarPresented = true
            }
            presentUtility(surface)
        }
    }

    func handleWebContentInteraction() {
        guard columnVisibility != .detailOnly || !isFloatingSidebarPresented else { return }
        utilityPresentation.handleInteraction(.webContent)
    }

    // MARK: - Actions - Command Palette

    func openLocation(_ address: String = "") {
        commandPaletteMode = .editLocation(address)
    }

    func presentCommandPalette() {
        commandPaletteMode = .newTab
    }

    func openNewTab(isStartPageSelected: Bool) {
        // A Start Page closes the command bar into its own field below.
        if isCommandPalettePresented, !isStartPageSelected {
            dismissCommandPalette()
            return
        }
        guard isStartPageSelected else {
            presentCommandPalette()
            return
        }
        commandPaletteMode = nil
        startPageFocusRequest &+= 1
    }

    func dismissCommandPalette() {
        commandPaletteMode = nil
    }

    // MARK: - Actions - Notices

    /// Shows `notice` at the top of this window, replacing any notice already
    /// there.
    func showNotice(_ notice: BrowserNotice) {
        self.notice = notice
        noticeRevision &+= 1
    }

    func showURLCopiedFeedback() {
        showNotice(.urlCopied)
    }

    func showPageZoomFeedback(_ label: String) {
        showNotice(.pageZoom(label))
    }
}

extension BrowserChromeState: BrowserStoreFirstObservable {}
