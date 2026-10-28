import Foundation

enum BrowserMediaSessionOrdering {
    /// First-published display order; playing, audible, then newest wins Now Playing.
    static func arbitration(of sessions: [BrowserMediaSessionSnapshot])
        -> (order: [BrowserMediaSessionSnapshot], nowPlaying: BrowserMediaSessionSnapshot?)?
    {
        guard sessions.count <= 64, Set(sessions.map(\.id)).count == sessions.count else { return nil }
        let ordered = sessions.sorted(by: precedes)
        let owner = ordered.filter { $0.playbackState != .none }.max { lhs, rhs in
            if lhs.playbackState != rhs.playbackState { return lhs.playbackState != .playing }
            if lhs.isAudible != rhs.isAudible { return !lhs.isAudible }
            return precedes(lhs, rhs)
        }
        return (ordered, owner)
    }

    private static func precedes(_ lhs: BrowserMediaSessionSnapshot, _ rhs: BrowserMediaSessionSnapshot) -> Bool {
        if lhs.orderingOrdinal != rhs.orderingOrdinal { return lhs.orderingOrdinal < rhs.orderingOrdinal }
        return lhs.id.id.utf16.lexicographicallyPrecedes(rhs.id.id.utf16)
    }
}
