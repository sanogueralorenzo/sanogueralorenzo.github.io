import SwiftUI

struct CrestSpaceSelectionRepair: ViewModifier {
    let browser: BrowserStore
    @Binding var selection: UUID?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: repair)
            .onChange(of: browser.spaceModels.map(\.id)) {
                repair()
            }
    }

    private func repair() {
        let repaired = browser.repairedSpaceSelection(selection)
        // Assigning an unchanged selection would invalidate the pane on every
        // Space edit, which is how a picker loses an open menu.
        guard repaired != selection else { return }
        selection = repaired
    }
}
