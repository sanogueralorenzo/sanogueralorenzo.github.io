using CrestCore.Contracts;

namespace CrestCore.Application;

/// The record the device store keeps for a saved window: what it showed and
/// when it was last used, as an order among the saved windows. A saved
/// window is always over the persistent session, so the record names no
/// workspace.
internal sealed record SavedWindow(Guid Id, Guid ShownSpaceId, IReadOnlyList<ShownTab> Tabs, IReadOnlyList<SplitColumnShares> Shares,
    long Used) {
    #region Actions - Equality

    public bool Equals(SavedWindow? other) => other is not null
        && Id == other.Id
        && ShownSpaceId == other.ShownSpaceId
        && Tabs.SequenceEqual(other.Tabs)
        && Shares.SequenceEqual(other.Shares)
        && Used == other.Used;

    public override int GetHashCode() => HashCode.Combine(Id, ShownSpaceId, Tabs.Count, Used);

    #endregion
}
