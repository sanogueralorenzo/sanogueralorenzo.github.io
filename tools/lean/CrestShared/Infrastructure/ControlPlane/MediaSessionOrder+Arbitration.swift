import Foundation

/// Media-session arbitration owned by the portable core, identical for the
/// WebKit bridge and Chromium's native session. Only ordering, lifecycle and
/// control facts cross, and the core alone decides which sessions take a card;
/// metadata, artwork and command endpoints stay in the store.
extension MediaSessionOrder {
    // MARK: - Actions - Answer

    /// The display order of `sessions` and the one that owns the system's Now
    /// Playing. Nil when the core cannot answer.
    static func arbitration(of sessions: [BrowserMediaSessionSnapshot])
        -> (order: [BrowserMediaSessionSnapshot], nowPlaying: BrowserMediaSessionSnapshot?)?
    {
        let question = MediaSessionOrder(
            sessions: sessions.map { session in
                MediaSessionEntry(
                    id: session.id.id, ordinal: session.orderingOrdinal, playback: session.playbackState.core,
                    isAudible: session.isAudible)
            })
        guard let answer = try? CrestCore.answer(question),
            answer.order.count == sessions.count, Set(answer.order).count == answer.order.count,
            answer.order.allSatisfy(sessions.indices.contains)
        else { return nil }
        let owner = answer.nowPlaying.flatMap { sessions.indices.contains($0) ? sessions[$0] : nil }
        return (answer.order.map { sessions[$0] }, owner)
    }
}
