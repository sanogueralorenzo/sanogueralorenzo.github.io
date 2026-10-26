import SwiftUI

extension View {
    /// Keep a pane's Space selection pointing at a Space that still exists.
    ///
    /// This is the other half of the eight-way duplication: every Space-scoped pane
    /// paired an `onAppear` with an `onChange` on the Space list and called the same
    /// private `repairSelection()` from both. The pairing is the contract — a pane
    /// that only repairs on appear shows an empty editor after a Space is deleted —
    /// so it is stated once here rather than reassembled per pane.
    func crestRepairsSpaceSelection(
        _ selection: Binding<UUID?>,
        in browser: BrowserStore
    ) -> some View {
        modifier(CrestSpaceSelectionRepair(browser: browser, selection: selection))
    }
}
