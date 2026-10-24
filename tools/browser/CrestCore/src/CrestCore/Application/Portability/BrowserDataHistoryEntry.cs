using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// One address of a Space's history as a Crest browser-data file keeps it,
/// without its fragment.
internal sealed record BrowserDataHistoryEntry(string Url, string Title, DateTimeOffset FirstVisitedAt, DateTimeOffset LastVisitedAt,
    int VisitCount) {
    #region Static Variables

    /// The most visits one address counts.
    public const int MaximumVisitCount = 1_000_000_000;

    #endregion

    #region Actions - Reading

    public static BrowserDataHistoryEntry Read(BrowserDataValue value) => new(value.Text("url"), value.Text("title"),
        value.Date("firstVisitedAt"), value.Date("lastVisitedAt"), value.Integer("visitCount"));

    /// The entries a Space keeps: each address once, its visits counted
    /// together, first and latest visit kept, and the title of its latest
    /// visit, newest first and at most as many as a Space keeps. Throws
    /// `ArchiveInvalid` for an entry a Space would not keep.
    public static IReadOnlyList<HistoryEntryState> Materialize(IEnumerable<BrowserDataHistoryEntry> entries, int maximum,
        Func<Guid> nextId) {
        ArgumentNullException.ThrowIfNull(entries);
        Dictionary<string, BrowserDataHistoryEntry> merged = new(StringComparer.Ordinal);
        foreach (var entry in entries) {
            var kept = entry.Materialize();
            if (!merged.TryGetValue(kept.Url, out var existing)) {
                merged[kept.Url] = kept;
                continue;
            }
            long visits = (long)existing.VisitCount + kept.VisitCount;
            if (visits > int.MaxValue) throw BrowserDataValue.Invalid();
            merged[kept.Url] = new(kept.Url, kept.LastVisitedAt >= existing.LastVisitedAt ? kept.Title : existing.Title,
                kept.FirstVisitedAt < existing.FirstVisitedAt ? kept.FirstVisitedAt : existing.FirstVisitedAt,
                kept.LastVisitedAt > existing.LastVisitedAt ? kept.LastVisitedAt : existing.LastVisitedAt, (int)visits);
        }
        return [.. merged.Values
            .OrderByDescending(entry => entry.LastVisitedAt)
            .ThenBy(entry => entry.Url, StringComparer.Ordinal)
            .Take(maximum)
            .Select(entry => new HistoryEntryState(nextId(), entry.Url, entry.Title, entry.FirstVisitedAt, entry.LastVisitedAt,
                entry.VisitCount))];
    }

    private BrowserDataHistoryEntry Materialize() {
        if (!ImportText.IsKept(Title, ImportText.MaximumTitle) || VisitCount is <= 0 or > MaximumVisitCount
            || FirstVisitedAt > LastVisitedAt || !ImportAddress.TryReadStored(Url, removesFragment: true, out var address)
            || address is null)
            throw BrowserDataValue.Invalid();
        return this with { Url = address.Value.Spelling };
    }

    #endregion

    #region Actions - Writing

    public static BrowserDataHistoryEntry From(HistoryEntryState entry) {
        ArgumentNullException.ThrowIfNull(entry);
        return new(ImportAddress.Written(entry.Url, removesFragment: true) ?? entry.Url, entry.Title, entry.FirstVisitedAt,
            entry.LastVisitedAt, entry.VisitCount);
    }

    public JsonObject Write() => new() {
        ["url"] = Url,
        ["title"] = Title,
        ["firstVisitedAt"] = ImportDate.UnixMilliseconds(FirstVisitedAt),
        ["lastVisitedAt"] = ImportDate.UnixMilliseconds(LastVisitedAt),
        ["visitCount"] = VisitCount
    };

    #endregion
}
