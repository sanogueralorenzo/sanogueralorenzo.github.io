namespace CrestCore.Contracts;

/// <summary>
/// The browsing session: its Spaces in order, the Space a launch opens, the marker of
/// a disposable first-install seed, Space deletions under way on this device and the
/// app-wide preferences. What each window shows is window state and never part of it.
/// <see cref="AppPreferences"/> is null until the settings kept before the core owned
/// them are imported.
/// </summary>
public sealed record SessionState(
    IReadOnlyList<SpaceState> Spaces,
    Guid? DefaultSpaceId,
    Guid? DisposableSeedMarker,
    IReadOnlyList<SpaceDeletionState> SpaceDeletions,
    AppPreferences? AppPreferences) {
    #region Static Variables

    /// The most Spaces a session holds.
    internal const int MaximumSpaces = 64;

    #endregion

    #region Variables

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<SpaceState> Spaces {
        get;
        init => field = [.. value];
    } = [.. Spaces];

    public IReadOnlyList<SpaceDeletionState> SpaceDeletions {
        get;
        init => field = [.. value];
    } = [.. SpaceDeletions];

    #endregion

    #region Actions - Spaces

    /// The Spaces of the session that are not going away.
    internal IReadOnlyList<SpaceState> StayingSpaces => [.. Spaces.Where(space => PendingDeletion(space.Id) is null)];

    /// The Space `id` names, or null when the session holds none.
    internal SpaceState? Space(Guid id) => Spaces.FirstOrDefault(space => space.Id == id);

    /// The Space `id` names. Throws `Rejected` with `UnknownSpace` when the
    /// session holds none.
    internal SpaceState KnownSpace(Guid id) => Space(id) ?? throw new Rejected(new UnknownSpace(id));

    /// The deletion under way of the Space `spaceId` names, or null while it stays.
    internal SpaceDeletionState? PendingDeletion(Guid spaceId) =>
        SpaceDeletions.FirstOrDefault(deletion => deletion.SpaceId == spaceId);

    /// The session with each of `edited` in place of the Space of its id.
    internal SessionState Replacing(params SpaceState[] edited) => this with {
        Spaces = [.. Spaces.Select(space => edited.FirstOrDefault(value => value.Id == space.Id) ?? space)]
    };

    /// The Spaces an import may join: none over a first launch's disposable
    /// Spaces, and never one going away.
    internal IReadOnlyList<SpaceState> ImportDestinations => DisposableSeedMarker is not null ? [] : StayingSpaces;

    /// How many new Spaces an import into the session has room for, as
    /// `ImportReviewedSpaces` counts them: a first launch's disposable Spaces
    /// make way for the import, and every other Space counts.
    internal int ImportRoom => Math.Max(0, MaximumSpaces - (DisposableSeedMarker is null ? Spaces.Count : 0));

    /// Throws `Rejected` with `SpaceLimitReached` when `additions` more Spaces
    /// would take a workspace holding `existing` past the limit.
    internal static void RequireSpaceCapacity(int existing, int additions) {
        if ((long)existing + additions > MaximumSpaces) throw new Rejected(new SpaceLimitReached(MaximumSpaces));
    }

    /// Throws `Rejected` with `CannotDeleteLastSpace` unless `spaceCount`
    /// Spaces leave one behind when one goes.
    internal static void RequireRemovable(int spaceCount) {
        if (spaceCount <= 1) throw new Rejected(new CannotDeleteLastSpace());
    }

    #endregion

    #region Actions - Equality

    public bool Equals(SessionState? other) => ReferenceEquals(this, other) || other is not null
        && Spaces.SequenceEqual(other.Spaces)
        && DefaultSpaceId == other.DefaultSpaceId
        && DisposableSeedMarker == other.DisposableSeedMarker
        && SpaceDeletions.SequenceEqual(other.SpaceDeletions)
        && AppPreferences == other.AppPreferences;

    public override int GetHashCode() => HashCode.Combine(Spaces.Count, DefaultSpaceId, DisposableSeedMarker, SpaceDeletions.Count);

    #endregion
}
