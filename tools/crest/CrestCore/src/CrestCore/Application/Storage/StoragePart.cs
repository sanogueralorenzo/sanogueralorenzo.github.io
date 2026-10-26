namespace CrestCore.Application;

/// A row of the stored `checkpoint` table, named by its part: the session
/// without history, the sync journal, and each Space's history. Earlier
/// releases wrote these names, and a rollback build still reads them.
internal sealed record StoragePart(string Name) {
    #region Variables

    public static readonly StoragePart Core = new("core");
    public static readonly StoragePart Journal = new("journal");

    private const string HistoryPrefix = "history.";

    /// Whether this part holds one Space's history.
    public bool IsHistory => Name.StartsWith(HistoryPrefix, StringComparison.Ordinal);

    #endregion

    #region Actions - Naming

    /// A Space's history part, spelled with the upper-case identity Swift wrote.
    public static StoragePart History(Guid spaceId) => new(HistoryPrefix + spaceId.ToString("D").ToUpperInvariant());

    #endregion
}
