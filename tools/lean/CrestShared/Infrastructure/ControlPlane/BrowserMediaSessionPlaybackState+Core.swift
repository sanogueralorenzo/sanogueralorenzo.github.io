import Foundation

extension BrowserMediaSessionPlaybackState {
    /// The state as the core's media rules read it.
    var core: MediaPlaybackState {
        switch self {
        case .none: .none
        case .paused: .paused
        case .playing: .playing
        }
    }
}
