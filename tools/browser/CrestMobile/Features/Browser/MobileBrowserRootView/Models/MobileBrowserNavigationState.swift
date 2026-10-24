import Foundation
import Observation

@Observable
@MainActor
final class MobileBrowserNavigationState {
    private(set) var presentation: MobileBrowserPresentation = .compact
    private var compactPagePresentationPhase: MobileCompactPagePresentationPhase
    private(set) var regularSidebarPresentation: BrowserSidebarPresentation
    private(set) var compactToolbarIsHidden = false
    let utilityPresentation = BrowserUtilityPresentationState()

    /// Whether a narrow window may float its sidebar over the page. When it
    /// may not, the full-screen tab viewer is its only sidebar, and the
    /// sidebar stays docked while the window is narrow.
    var allowsCompactFloatingSidebar: Bool {
        didSet {
            guard allowsCompactFloatingSidebar != oldValue, hasAdaptedPresentation else { return }
            dockIfFloatingIsNotAllowed()
        }
    }

    @ObservationIgnored
    private let transientSidebarDismissalDelay: Duration
    @ObservationIgnored
    private var transientSidebarDismissalTask: Task<Void, Never>?
    @ObservationIgnored
    private var transientSidebarDismissalIsPaused = false
    @ObservationIgnored
    private var lockedSpaceKeepsSidebarVisible = false
    /// The window has measured itself, so `presentation` is its own.
    @ObservationIgnored
    private var hasAdaptedPresentation = false
    /// Whether a narrow window docked a sidebar the person had hidden at
    /// regular width, which hides again once the window widens.
    @ObservationIgnored
    private var dockedHiddenSidebarWhileNarrow = false
    /// Whether the window put its docked sidebar away because a fold divides
    /// a split's pages. It docks again once the fold no longer does, and the
    /// window's saved state never hears of it.
    private(set) var hidSidebarForFoldedSplit = false

    init(
        regularSidebarIsPresented: Bool = true,
        initiallyShowsCompactPage: Bool = false,
        allowsCompactFloatingSidebar: Bool = true,
        transientSidebarDismissalDelay: Duration = .seconds(5)
    ) {
        regularSidebarPresentation =
            regularSidebarIsPresented
            ? .docked
            : .collapsed
        self.allowsCompactFloatingSidebar = allowsCompactFloatingSidebar
        self.transientSidebarDismissalDelay = transientSidebarDismissalDelay
        compactPagePresentationPhase =
            initiallyShowsCompactPage
            ? .page
            : .tabViewer
    }

    var defersPageActivation: Bool {
        presentation.presentsPageOverTabViewer && !compactShowsPage
    }

    var compactShowsPage: Bool {
        compactPagePresentationPhase.showsPage
    }

    var compactPageIsFullyPresented: Bool {
        compactPagePresentationPhase == .page
    }

    var compactTabViewerChromeIsVisible: Bool {
        compactPagePresentationPhase == .tabViewer
    }

    var regularSidebarIsPresented: Bool {
        regularSidebarPresentation.showsSidebar
    }

    var regularSidebarIsDocked: Bool {
        regularSidebarPresentation == .docked
    }

    /// A narrow phone's full-screen tab viewer is its docked sidebar. Once the
    /// page is presented, the shared sidebar can only be floating or collapsed;
    /// a persisted regular-width dock state must not force the phone into the
    /// expanded shell.
    var compactSidebarPresentation: BrowserSidebarPresentation {
        guard compactShowsPage else { return .docked }
        return regularSidebarPresentation == .floating
            ? .floating
            : .collapsed
    }

    func selectTab() {
        presentation.selectTab(on: self)
    }

    /// Brings the page a row selection chose up over a narrow window's tab
    /// viewer.
    func presentPageFromTabViewer() {
        if compactPagePresentationPhase == .tabViewer {
            // The full-screen phone tab viewer is the docked sidebar. A
            // normal row selection must therefore enter the original
            // docked detail flow even if a prior window session last used
            // the floating sidebar. The Undock button takes the separate
            // toggleCompactSidebar path and keeps the floating mode.
            dockRegularSidebar()
        }
        compactToolbarIsHidden = false
        compactPagePresentationPhase = .presentingPage
    }

    /// Setup can finish before the new browser root has resolved its width.
    /// Retain the requested page even if the previous presentation was regular.
    func presentSelectedTabAfterSetup() {
        dockRegularSidebar()
        compactToolbarIsHidden = false
        compactPagePresentationPhase = .presentingPage
    }

    func showTabViewer() {
        compactToolbarIsHidden = false
        compactPagePresentationPhase = .tabViewer
        presentation.placeSidebarForTabViewer(on: self)
    }

    func prepareForSpaceSwitch() {
        showTabViewer()
    }

    /// A lock is a privacy-state change inside the selected Space, not a new
    /// navigation mode. Keep the sidebar presentation the user is already in:
    /// a docked phone returns to its full-screen tab viewer, while a floating
    /// or collapsed sidebar becomes a persistent floating lock surface over
    /// the existing window.
    func prepareForLockedSpace() {
        lockedSpaceKeepsSidebarVisible = true
        compactToolbarIsHidden = false
        presentation.prepareForLockedSpace(on: self)
    }

    /// A narrow window keeps an undocked sidebar floating over the page it
    /// shows, and otherwise returns to its full-screen tab viewer.
    func keepLockedSpaceOverCompactPage() {
        if compactShowsPage, regularSidebarPresentation != .docked {
            cancelTransientSidebarDismissal()
            regularSidebarPresentation = .floating
        } else {
            showTabViewer()
        }
    }

    /// A regular window floats a hidden sidebar over the page, so the lock
    /// stays on screen.
    func keepLockedSpaceBesidePage() {
        cancelTransientSidebarDismissal()
        if regularSidebarPresentation == .collapsed {
            regularSidebarPresentation = .floating
        }
    }

    func finishLockedSpaceTransition() -> MobileBrowserSpaceSwitchDestination {
        lockedSpaceKeepsSidebarVisible = false
        return MobileBrowserSpaceSwitchDestination.afterLeavingLockedSpace(
            in: presentation,
            sidebarPresentation: regularSidebarPresentation
        )
    }

    func hideCompactToolbar() {
        guard presentation.presentsPageOverTabViewer, compactShowsPage else { return }
        compactToolbarIsHidden = true
    }

    func showCompactToolbar() {
        compactToolbarIsHidden = false
    }

    func completePagePresentation() {
        guard compactPagePresentationPhase == .presentingPage else { return }
        compactPagePresentationPhase = .page
    }

    /// The stable view state changes
    /// immediately while SwiftUI supplies only the visual morph between it and
    /// the selected tab row. There is no modal dismissal phase to stall in.
    func dismissPageToTabViewer() {
        showTabViewer()
    }

    func showSidebar() {
        showTabViewer()
    }

    func showRegularSidebar() {
        regularSidebarPresentation = .floating
        scheduleTransientSidebarDismissal()
    }

    func dockRegularSidebar() {
        cancelTransientSidebarDismissal()
        regularSidebarPresentation = .docked
    }

    func hideRegularSidebar() {
        cancelTransientSidebarDismissal()
        regularSidebarPresentation = .collapsed
    }

    func toggleRegularSidebar() {
        regularSidebarPresentation.toggle(on: MobileRegularSidebarToggle(navigation: self))
    }

    /// Uses the same three sidebar states as regular-width windows while
    /// adapting only what "docked" means on a narrow phone. Without a
    /// floating sidebar it moves between the tab viewer and the page.
    func toggleCompactSidebar() {
        compactSidebarPresentation.toggle(on: MobileCompactSidebarToggle(navigation: self))
    }

    /// Brings the page up over a narrow window's tab viewer, with its toolbar.
    func presentCompactPage() {
        compactToolbarIsHidden = false
        compactPagePresentationPhase = .presentingPage
    }

    func handleRegularSidebarInteraction() {
        scheduleTransientSidebarDismissal()
    }

    func handleRegularPageInteraction() {
        guard regularSidebarPresentation == .floating else { return }
        hideRegularSidebar()
    }

    func setTransientSidebarDismissalPaused(_ isPaused: Bool) {
        guard transientSidebarDismissalIsPaused != isPaused else { return }
        transientSidebarDismissalIsPaused = isPaused
        if isPaused {
            transientSidebarDismissalTask?.cancel()
            transientSidebarDismissalTask = nil
        } else {
            scheduleTransientSidebarDismissal()
        }
    }

    func adapt(to presentation: MobileBrowserPresentation) {
        self.presentation = presentation
        hasAdaptedPresentation = true
        presentation.adapt(self)
        dockIfFloatingIsNotAllowed()
    }

    /// Puts a docked sidebar away while a fold divides a split's pages, so the
    /// pages take a side each and the sidebar floats over them when called,
    /// and docks it again when the fold no longer does.
    func adaptToFoldedSplit(_ splitsPagesAtFold: Bool) {
        if splitsPagesAtFold {
            guard regularSidebarPresentation == .docked else { return }
            hidSidebarForFoldedSplit = true
            hideRegularSidebar()
        } else if hidSidebarForFoldedSplit {
            hidSidebarForFoldedSplit = false
            // The sidebar was docked before the fold put it away, so a narrow
            // window that docked it again meanwhile must not hide it on
            // widening.
            dockedHiddenSidebarWhileNarrow = false
            if regularSidebarPresentation != .docked {
                dockRegularSidebar()
            }
        }
    }

    /// A window that widens shows its toolbar, and hides again a sidebar it
    /// docked only because it was narrow.
    func leaveNarrowWidth() {
        compactToolbarIsHidden = false
        if dockedHiddenSidebarWhileNarrow, regularSidebarPresentation == .docked {
            hideRegularSidebar()
        }
        dockedHiddenSidebarWhileNarrow = false
    }

    /// A narrow window that may not float its sidebar keeps it docked, which
    /// keeps the page full screen under the compact toolbar. A sidebar hidden
    /// at regular width hides again when the window widens.
    private func dockIfFloatingIsNotAllowed() {
        guard presentation.presentsPageOverTabViewer, !allowsCompactFloatingSidebar,
            regularSidebarPresentation != .docked
        else {
            return
        }
        dockedHiddenSidebarWhileNarrow = true
        dockRegularSidebar()
    }

    private func scheduleTransientSidebarDismissal() {
        guard regularSidebarPresentation == .floating,
            !transientSidebarDismissalIsPaused,
            !lockedSpaceKeepsSidebarVisible
        else { return }
        transientSidebarDismissalTask?.cancel()
        let delay = transientSidebarDismissalDelay
        transientSidebarDismissalTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.hideRegularSidebar()
        }
    }

    private func cancelTransientSidebarDismissal() {
        transientSidebarDismissalTask?.cancel()
        transientSidebarDismissalTask = nil
        transientSidebarDismissalIsPaused = false
    }
}
