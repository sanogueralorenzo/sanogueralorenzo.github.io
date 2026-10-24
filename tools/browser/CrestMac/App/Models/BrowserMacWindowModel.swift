import AppKit
import Observation
import SwiftUI

@Observable
@MainActor
final class BrowserMacWindowModel {
    let request: BrowserMacWindowRequest
    let browser: BrowserStore
    let pages: BrowserPagePool
    let chrome: BrowserChromeState
    let transientBrowsing: BrowserTransientBrowsingCoordinator
    let spaceSettingsPresentation = BrowserSpaceSettingsPresentationState()
    let windowState: BrowserWindowStateStore
    /// Whether the window may close when the person asks: the core asks the
    /// pages that go with it, which a temporary window's are and a normal
    /// window's, which the other windows keep, are not.
    let closeGate: BrowserWindowCloseGate
    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored var tearOffPlacement: BrowserMacTabTearOffPlacement?

    var id: UUID { request.id }
    var isTemporary: Bool { request.kind == .temporary }

    init(
        request: BrowserMacWindowRequest, browser: BrowserStore, pages: BrowserPagePool,
        transientBrowsing: BrowserTransientBrowsingCoordinator, windowState: BrowserWindowStateStore
    ) {
        self.request = request
        self.browser = browser
        self.pages = pages
        self.transientBrowsing = transientBrowsing
        self.windowState = windowState
        // Page commands act on a Peek only once it opens, not while its link
        // is still being dragged.
        pages.isPeekOpen = { [weak transientBrowsing] request in
            transientBrowsing?.presentationPhase(for: request) == .committed
        }
        // Closes as the Peek's own Close button does.
        pages.dismissPeek = { [weak transientBrowsing] request in
            let animation = CrestMotion.peekDismissal.unlessReducingMotion(
                NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            withAnimation(animation) { _ = transientBrowsing?.dismissPeek(request) }
        }
        closeGate = BrowserWindowCloseGate(core: browser.core) { [windowID = browser.windowID] in
            PrepareToCloseWindows(requestID: UUID(), windowIDs: [windowID])
        }
        chrome = BrowserChromeState(
            sidebarIsPresented: windowState.sidebarIsPresented ?? true,
            utilityPresentation: BrowserUtilityPresentationState(defaults: nil))
    }
}
