namespace CrestCore.Contracts;

/// <summary>
/// One list of rows a Space's sidebar shows together: the top level of
/// <see cref="Section"/> when <see cref="FolderId"/> is null, or else the inside of that
/// folder, which lives in <see cref="Section"/>. A list holds its rows whether or not its
/// folder or section is collapsed.
/// </summary>
public sealed record SidebarList(TabPlacement Section, Guid? FolderId, IReadOnlyList<SidebarRow> Rows) {
    #region Variables

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<SidebarRow> Rows {
        get;
        init => field = [.. value];
    } = [.. Rows];

    #endregion

    #region Actions - Equality

    public bool Equals(SidebarList? other) => other is not null
        && Section == other.Section
        && FolderId == other.FolderId
        && Rows.SequenceEqual(other.Rows);

    public override int GetHashCode() => HashCode.Combine(Section, FolderId, Rows.Count);

    #endregion
}
