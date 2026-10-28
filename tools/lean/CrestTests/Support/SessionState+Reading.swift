import Foundation

@testable import Crest

/// Readers over the read model's values, for tests that read a session
/// through `BrowserStore.snapshot`.
extension SessionState {
    /// The Space with this identity, or nil when the session holds none.
    func space(id: UUID) -> SpaceState? {
        spaces.first { $0.id == id }
    }

    /// The open tab with this identity in any Space, or nil when no Space
    /// holds it open.
    func tab(id: UUID) -> TabState? {
        spaces.lazy.compactMap { space in space.tabs.first { $0.id == id } }.first
    }
}
