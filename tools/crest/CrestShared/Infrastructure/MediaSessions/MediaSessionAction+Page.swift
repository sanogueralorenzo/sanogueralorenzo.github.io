import Foundation

extension MediaSessionAction {
    /// The action as the page's Media Session API spells it, which Crest's
    /// page bridge reports and takes.
    var pageName: String {
        switch self {
        case .play: "play"
        case .pause: "pause"
        case .previousTrack: "previoustrack"
        case .nextTrack: "nexttrack"
        }
    }

    /// The action a page bridge names, or nil for one Crest does not offer.
    init?(pageName: String) {
        guard let action = Self.allCases.first(where: { $0.pageName == pageName }) else { return nil }
        self = action
    }
}
