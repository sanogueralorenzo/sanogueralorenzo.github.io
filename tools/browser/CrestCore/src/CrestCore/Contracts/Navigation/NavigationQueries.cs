namespace CrestCore.Contracts;

/// For each asked address, in order, the address history keeps for it, or
/// null for one history does not keep.
public sealed record HistoryAddressList(IReadOnlyList<string?> Normalized);

/// Whether two addresses name one page.
public sealed record PageMatch(bool IsSamePage);
