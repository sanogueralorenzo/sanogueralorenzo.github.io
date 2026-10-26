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

    /// `utilityDefaults` is where the window's utility lists keep what the
    /// person chose for them, shared with every other window's.
    init(
        request: BrowserMacWindowRequest, browser: BrowserStore, pages: BrowserPagePool,
        windowState: BrowserWindowStateStore
    ) {
        self.request = request
        self.browser = browser
        self.pages = pages
        self.windowState = windowState
        closeGate = BrowserWindowCloseGate(core: browser.core) { [windowID = browser.windowID] in
            PrepareToCloseWindows(requestID: UUID(), windowIDs: [windowID])
        }
        chrome = BrowserChromeState(
            utilityPresentation: BrowserUtilityPresentationState(defaults: nil))
    }
}
