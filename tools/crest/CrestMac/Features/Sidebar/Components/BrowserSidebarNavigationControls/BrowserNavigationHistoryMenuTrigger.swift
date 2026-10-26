import SwiftUI

/// Lays a `BrowserNavigationHistoryMenuTriggerView` over a history control and
/// keeps it reading the control's current history and actions.
struct BrowserNavigationHistoryMenuTrigger: NSViewRepresentable {
    let anchor: BrowserNavigationHistoryMenuAnchor
    let items: () -> [BrowserNavigationHistoryItem]
    let emptyTitle: LocalizedStringResource
    let choose: (BrowserNavigationHistoryItem) -> Void
    let showFullHistory: () -> Void

    func makeNSView(context: Context) -> BrowserNavigationHistoryMenuTriggerView {
        let view = BrowserNavigationHistoryMenuTriggerView()
        attach(to: view)
        return view
    }

    func updateNSView(_ nsView: BrowserNavigationHistoryMenuTriggerView, context: Context) {
        attach(to: nsView)
    }

    private func attach(to view: BrowserNavigationHistoryMenuTriggerView) {
        view.items = items
        view.emptyTitle = emptyTitle
        view.choose = choose
        view.showFullHistory = showFullHistory
        anchor.view = view
    }
}
