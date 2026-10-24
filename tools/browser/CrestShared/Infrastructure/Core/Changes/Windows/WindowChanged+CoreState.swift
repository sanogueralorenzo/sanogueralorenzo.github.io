import Foundation

extension WindowChanged {
    /// A window that stays open keeps its object, which notifies only for
    /// what it shows differently, so another window's change never reaches it.
    @MainActor func apply(to state: CoreState) {
        if let window = state.windows[self.window.id] {
            window.update(self.window)
        } else {
            state.publish(WindowStateModel(self.window), forKey: self.window.id, into: \.windowsStorage, as: \.windows)
        }
    }
}
