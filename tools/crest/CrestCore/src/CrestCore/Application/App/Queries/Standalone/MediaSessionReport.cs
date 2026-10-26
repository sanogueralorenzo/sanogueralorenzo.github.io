using CrestCore.Application;

namespace CrestCore.Contracts;

/// What the media-session store does with one page report, given what it
/// remembers of the reporting document, how many identities it remembers and
/// the next ordinal it would give. Refused with `InvalidMediaSessionCount` for
/// a negative count.
///
/// Media-session arbitration is identical for every engine. Each document
/// reports sequenced events. Stale and retired reports are dropped; a report
/// can retire its document, withdraw its card, or publish it, and a published
/// document supersedes every other document of its tab. Only media a person
/// can control is published: a session offering play or pause, the transport
/// a player has. A notification chime or other short sound a script plays
/// offers neither, so it never takes a card or the system's Now Playing. A
/// muted session already shown keeps its card, since an engine may withdraw a
/// muted page's controls and the card is where it is unmuted. The store
/// remembers a bounded window of identities.
public sealed record MediaSessionReport(MediaSessionEvent Event, MediaSessionIdentity Identity, int RetainedIdentities,
    ulong NextOrdinal) : StandaloneQuery<MediaSessionEventDecision> {
    #region Static Variables

    internal const int MaximumRetainedIdentities = 512;

    #endregion

    #region Variables

    internal MediaSessionEventDecision Decision {
        get {
            ArgumentNullException.ThrowIfNull(Event);
            ArgumentNullException.ThrowIfNull(Identity);
            if (RetainedIdentities < 0) throw new Rejected(new InvalidMediaSessionCount(RetainedIdentities));
            if (Identity.IsRetired || Event.Sequence <= (Identity.LastSequence ?? 0))
                return new(false, 0, MediaSessionDisposition.Clear, false, null, NextOrdinal, false);
            int retained = RetainedIdentities + (Identity.LastSequence is null ? 1 : 0);
            int evict = Math.Max(0, retained - MaximumRetainedIdentities);
            if (Event.IsInvalidated) return new(true, evict, MediaSessionDisposition.Retire, false, null, NextOrdinal, false);
            if (!Event.HasActiveSession || !IsControllable)
                return new(true, evict, MediaSessionDisposition.Clear, false, null, NextOrdinal, false);
            ulong ordinal = Identity.Ordinal ?? NextOrdinal;
            ulong next = Identity.Ordinal is null ? unchecked(NextOrdinal + 1) : NextOrdinal;
            // A card the person hid stays hidden until playback starts afresh.
            bool clearsDismissal = Identity.IsDismissed && Identity.PreviousPlayback != MediaPlaybackState.Playing
                && Event.Playback == MediaPlaybackState.Playing;
            return new(true, evict, MediaSessionDisposition.Publish, true, ordinal, next, clearsDismissal);
        }
    }

    // `PreviousPlayback` is known only while the document's card is shown.
    private bool IsControllable =>
        Event.Actions.Contains(MediaSessionAction.Play) || Event.Actions.Contains(MediaSessionAction.Pause)
        || (Event.IsMuted && Identity.PreviousPlayback is not null);

    #endregion

    #region Actions - Answering

    internal override MediaSessionEventDecision Answer(StandaloneContext context) => Decision;

    #endregion
}
