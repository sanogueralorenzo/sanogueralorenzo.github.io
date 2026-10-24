import Foundation
import Observation

/// One window's layout: its sidebar, which this device keeps in `layouts`,
/// and the split columns the core keeps for the window `browser` presents.
@Observable
@MainActor
final class BrowserWindowStateStore {
    private(set) var state: BrowserWindowState
    @ObservationIgnored private let layouts: BrowserWindowLayouts
    @ObservationIgnored private let browser: BrowserStore

    var id: UUID { state.id }
    var sidebarWidth: Double? { state.sidebarWidth }
    var sidebarIsPresented: Bool? { state.sidebarIsPresented }

    init(id: UUID, browser: BrowserStore, layouts: BrowserWindowLayouts) {
        self.layouts = layouts
        self.browser = browser
        state = layouts.layout(for: id) ?? BrowserWindowState(id: id)
    }

    func captureSidebar(width: Double? = nil, isPresented: Bool? = nil) {
        let previousState = state
        state.captureSidebar(width: width, isPresented: isPresented)
        guard state != previousState else { return }
        layouts.save(state)
    }

    func splitColumnFractions(for groupID: UUID) -> [Double]? {
        browser.window.splitColumnFractions(for: groupID)
    }

    func captureSplitLayout(fractions: [Double], for groupID: UUID) {
        browser.resizeSplitColumns(fractions, for: groupID)
    }

    func removePersistedState() {
        layouts.remove(id: id)
    }
}
