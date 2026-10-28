import SwiftUI

/// Observes the whole selection snapshot so each shell can reconcile a transition once.
struct BrowserRootSelectionObserver<Selection: Equatable>: ViewModifier {
    let selection: Selection
    let selectionChanged: (Selection, Selection) -> Void

    func body(content: Content) -> some View {
        content.onChange(of: selection) { previous, current in
            selectionChanged(previous, current)
        }
    }
}
