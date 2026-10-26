import Observation
import SwiftUI

@Observable
@MainActor
final class BrowserChromeState {
    // MARK: - Variables

    let utilityPresentation: BrowserUtilityPresentationState
    var isSidebarPresented: Bool {
        get { observed(\.isSidebarPresentedStorage, as: \.isSidebarPresented) }
        set { publish(newValue, into: \.isSidebarPresentedStorage, as: \.isSidebarPresented) }
    }
    @ObservationIgnored private var isSidebarPresentedStorage: Bool
    private(set) var commandPaletteMode: BrowserCommandPaletteMode? {
        get { observed(\.commandPaletteModeStorage, as: \.commandPaletteMode) }
        set { publish(newValue, into: \.commandPaletteModeStorage, as: \.commandPaletteMode) }
    }
    @ObservationIgnored private var commandPaletteModeStorage: BrowserCommandPaletteMode?
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
        sidebarIsPresented: Bool = false,
        utilityPresentation: BrowserUtilityPresentationState =
            BrowserUtilityPresentationState()
    ) {
        isSidebarPresentedStorage = sidebarIsPresented
        self.utilityPresentation = utilityPresentation
    }

    // MARK: - Actions - Sidebar

    /// Hiding cancels utility presentation and pending input before an asynchronous view update can mount it.
    func hideSidebar() {
        utilityPresentation.dismiss()
        isSidebarPresented = false
    }

    func showSidebar() {
        isSidebarPresented = true
    }

    /// Utility commands temporarily reveal their list in the floating sidebar.
    func presentUtility(_ surface: BrowserUtilitySurface) {
        showSidebar()
        utilityPresentation.present(surface)
    }

    func toggleUtility(_ surface: BrowserUtilitySurface) {
        if utilityPresentation.surface == surface, isSidebarPresented {
            hideSidebar()
        } else {
            presentUtility(surface)
        }
    }

    func handleWebContentInteraction() {
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
