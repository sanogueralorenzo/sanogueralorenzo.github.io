namespace CrestCore.Contracts;

#region Queries

/// The ordering, lifecycle and control facts of one page media-session report.
/// Engines sequence reports per document; metadata and artwork stay native.
/// `Actions` are the playback controls the session offers: WebKit's bridge
/// offers play and pause for a player that passes Picture in Picture's player
/// rule, and Chromium's session for media it can control, never for a short
/// sound a script plays.
public sealed record MediaSessionEvent(ulong Sequence, bool IsInvalidated, bool HasActiveSession, MediaPlaybackState Playback,
    bool IsMuted, IReadOnlyList<MediaSessionAction> Actions);

/// The store's instructions for one report. A rejected report changes nothing.
/// `EvictOldest` is how many of the oldest remembered identities to forget
/// once this one is recorded. A published session supersedes every other
/// document under the same tab, keeps `Ordinal` for ordering, and the store
/// continues from `NextOrdinal`.
public sealed record MediaSessionEventDecision(bool Accepted, int EvictOldest, MediaSessionDisposition Disposition,
    bool SupersedesTabSiblings, ulong? Ordinal, ulong NextOrdinal, bool ClearsDismissal);

/// What an accepted report does to its session: retire the document for good,
/// withdraw its card while keeping its identity, or publish it.
public enum MediaSessionDisposition { Retire, Clear, Publish }

/// What the store remembers about the reporting document: whether it was
/// retired, the last sequence it accepted, the ordinal it was given, whether the
/// person hid its card, and the playback state it last published, which is
/// null while the document has no card.
public sealed record MediaSessionIdentity(bool IsRetired, ulong? LastSequence, ulong? Ordinal, bool IsDismissed,
    MediaPlaybackState? PreviousPlayback);

#endregion

#region Rejections

/// Two sessions to order share one identity.
public sealed record DuplicateMediaSession(string Id) : Rejection;

/// A count of remembered identities below zero.
public sealed record InvalidMediaSessionCount(int Count) : Rejection;

/// More sessions than the store orders at once.
public sealed record MediaSessionLimitReached(int Maximum) : Rejection;

#endregion

#region Models

/// Published sessions in display order, as indices into the caller's list, and
/// the one session that owns the system's Now Playing, if any.
public sealed record MediaSessionArbitration(IReadOnlyList<int> Order, int? NowPlaying);

/// One published session as ordering and Now Playing ownership see it.
public sealed record MediaSessionEntry(string Id, ulong Ordinal, MediaPlaybackState Playback, bool IsAudible);

/// What a page's media session reports: nothing observed yet, paused or playing.
public enum MediaPlaybackState { None, Paused, Playing }

#endregion
