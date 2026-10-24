namespace CrestCore.Contracts;

/// What one open window shows: the Space on screen, the tab it shows in each
/// Space it has shown, and the column shares of the split groups it has
/// resized. A Space without an entry has not been shown in this window yet; an
/// entry without a tab shows nothing. `Cards` are the tabs its content shows
/// side by side in each Space where it shows a tab.
/// `UnavailableCommands` are the commands the window cannot run now. The
/// Apple read model keeps it in a hand-written `WindowStateModel`, which also
/// observes each shown tab on its own; a test there fails when this record
/// gains a field the model misses.
public sealed record WindowState(Guid Id, Guid WorkspaceId, Guid ShownSpaceId, IReadOnlyList<ShownTab> ShownTabs,
    IReadOnlyList<SplitColumnShares> SplitColumnShares, IReadOnlyList<ShownCards> Cards,
    IReadOnlyList<ShortcutCommand> UnavailableCommands) {
    #region Actions - Equality

    public bool Equals(WindowState? other) => other is not null
        && Id == other.Id
        && WorkspaceId == other.WorkspaceId
        && ShownSpaceId == other.ShownSpaceId
        && ShownTabs.SequenceEqual(other.ShownTabs)
        && SplitColumnShares.SequenceEqual(other.SplitColumnShares)
        && Cards.SequenceEqual(other.Cards)
        && UnavailableCommands.SequenceEqual(other.UnavailableCommands);

    public override int GetHashCode() => HashCode.Combine(Id, WorkspaceId, ShownSpaceId, ShownTabs.Count);

    #endregion
}
