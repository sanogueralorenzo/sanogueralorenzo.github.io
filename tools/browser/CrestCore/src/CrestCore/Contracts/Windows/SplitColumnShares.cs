namespace CrestCore.Contracts;

/// The share of a window's width each column of a split group takes, in
/// column order, summing to one.
public sealed record SplitColumnShares(Guid GroupId, IReadOnlyList<double> Shares) {
    #region Actions - Equality

    public bool Equals(SplitColumnShares? other) => other is not null && GroupId == other.GroupId && Shares.SequenceEqual(other.Shares);

    public override int GetHashCode() => HashCode.Combine(GroupId, Shares.Count);

    #endregion
}
