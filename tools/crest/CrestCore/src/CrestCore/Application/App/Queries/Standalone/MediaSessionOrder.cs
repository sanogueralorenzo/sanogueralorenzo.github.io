using CrestCore.Application;

namespace CrestCore.Contracts;

/// The display order of the published sessions and the one that owns the
/// system's Now Playing. Refused with `MediaSessionLimitReached` past
/// `MaximumSessions` and `DuplicateMediaSession` for a repeated identity.
/// Published sessions are shown in first-published order, and one of them
/// owns the system's Now Playing: playing before paused, audible before
/// silent, then the most recently published.
public sealed record MediaSessionOrder(IReadOnlyList<MediaSessionEntry> Sessions) : StandaloneQuery<MediaSessionArbitration> {
    #region Static Variables

    public const int MaximumSessions = 64;

    #endregion

    #region Variables

    internal MediaSessionArbitration Arbitration {
        get {
            ArgumentNullException.ThrowIfNull(Sessions);
            if (Sessions.Count > MaximumSessions)
                throw new Rejected(new MediaSessionLimitReached(MaximumSessions));
            if (Sessions.GroupBy(session => session.Id, StringComparer.Ordinal).FirstOrDefault(group => group.Count() > 1) is { } repeated)
                throw new Rejected(new DuplicateMediaSession(repeated.Key));
            var order = Enumerable.Range(0, Sessions.Count).ToList();
            order.Sort((lhs, rhs) => Compare(Sessions[lhs], Sessions[rhs]));
            int? owner = null;
            for (int index = 0; index < Sessions.Count; index++) {
                if (Sessions[index].Playback == MediaPlaybackState.None) continue;
                if (owner is not { } current || OwnsBefore(Sessions[index], Sessions[current])) owner = index;
            }
            return new(order, owner);
        }
    }

    #endregion

    #region Actions - Answering

    internal override MediaSessionArbitration Answer(StandaloneContext context) => Arbitration;

    private static int Compare(MediaSessionEntry lhs, MediaSessionEntry rhs) =>
        lhs.Ordinal != rhs.Ordinal ? lhs.Ordinal.CompareTo(rhs.Ordinal) : string.CompareOrdinal(lhs.Id, rhs.Id);

    private static bool OwnsBefore(MediaSessionEntry candidate, MediaSessionEntry current) {
        if (candidate.Playback != current.Playback) return candidate.Playback > current.Playback;
        if (candidate.IsAudible != current.IsAudible) return candidate.IsAudible;
        return Compare(candidate, current) > 0;
    }

    #endregion
}
