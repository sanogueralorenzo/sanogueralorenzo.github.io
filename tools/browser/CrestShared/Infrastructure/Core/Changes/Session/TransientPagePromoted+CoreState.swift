import Foundation

extension TransientPagePromoted {
    /// A promoted page changes no state of its own: the session's changes
    /// before it carry the new tab, and the window that promoted it reads it
    /// from the changes its intent answered.
    @MainActor func apply(to state: CoreState) {}
}
