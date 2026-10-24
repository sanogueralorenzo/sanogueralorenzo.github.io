namespace CrestCore.Contracts;

/// The tabs a window's content shows side by side in one Space, in column
/// order: the members of the split that holds the tab the window shows
/// there, with that split's id, or the tab alone with none.
public sealed record ShownCards(Guid SpaceId, IReadOnlyList<Guid> TabIds, Guid? SplitGroupId) {
    #region Actions - Equality

    public bool Equals(ShownCards? other) => other is not null && SpaceId == other.SpaceId
        && TabIds.SequenceEqual(other.TabIds) && SplitGroupId == other.SplitGroupId;

    public override int GetHashCode() => HashCode.Combine(SpaceId, TabIds.Count, SplitGroupId);

    #endregion
}
