namespace CrestCore.Contracts;

/// <summary>
/// One row a Space's sidebar lists. <see cref="Members"/> are the tabs the row shows: a
/// tab row's own tab, or a split's tabs in order; a folder row shows none, since its
/// inside is a list of its own. <see cref="ParentFolderId"/> is the folder whose
/// inside lists the row, and <see cref="Depth"/> how many folders hold it.
/// </summary>
public sealed record SidebarRow(Guid Id, SidebarRowKind Kind, Guid? ParentFolderId, int Depth, IReadOnlyList<Guid> Members) {
    #region Variables

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<Guid> Members {
        get;
        init => field = [.. value];
    } = [.. Members];


    /// <summary>What the row places in the sidebar's order: a folder itself, or the tabs
    /// the row shows.</summary>
    public IEnumerable<Guid> Listed => Kind.OpensList ? [Id] : Members;

    #endregion

    #region Actions - Equality

    public bool Equals(SidebarRow? other) => other is not null
        && Id == other.Id
        && Kind == other.Kind
        && ParentFolderId == other.ParentFolderId
        && Depth == other.Depth
        && Members.SequenceEqual(other.Members);

    public override int GetHashCode() => HashCode.Combine(Id, Kind, ParentFolderId, Depth, Members.Count);

    #endregion
}
