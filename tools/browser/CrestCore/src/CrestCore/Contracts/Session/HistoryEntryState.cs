using CrestCore.Domain;

namespace CrestCore.Contracts;

/// <summary>One address in a Space's history, with its first and latest visit.</summary>
public sealed record HistoryEntryState(Guid Id, string Url, string Title, DateTimeOffset FirstVisitedAt,
    DateTimeOffset LastVisitedAt, int VisitCount) {
    #region Static Variables

    /// The most entries a Space's history keeps.
    internal const int MaximumEntries = 5000;

    #endregion

    #region Actions - Visits

    /// A newest-first history after a visit to `url`, capped at
    /// `MaximumEntries`: the page's entry, with one more visit, goes first, and
    /// a new entry takes `newId`. Null for an address history does not keep,
    /// including one whose normal form normalizes to another, which leaves
    /// it as it was.
    internal static IReadOnlyList<HistoryEntryState>? Visit(IReadOnlyList<HistoryEntryState> history, string url, string? title,
        DateTimeOffset now, Guid newId) => Visit(history, url, title, now, newId, MaximumEntries);

    /// A visit to a history that keeps at most `limit` entries.
    internal static IReadOnlyList<HistoryEntryState>? Visit(IReadOnlyList<HistoryEntryState> history, string url, string? title,
        DateTimeOffset now, Guid newId, int limit) {
        ArgumentNullException.ThrowIfNull(history);
        if (new WebAddress(url).Normalized is not { } normalized || new WebAddress(normalized).Normalized != normalized) return null;
        var previous = AddressIndex.Of(history).Entry(normalized);
#if CREST_CROSS_CHECKS
        if (previous != history.FirstOrDefault(entry => entry.Url == normalized))
            throw new System.Diagnostics.UnreachableException("The address index names another entry than the history's newest for the address.");
#endif
        var visit = Record(normalized, title, now, newId, previous);
        var visited = new List<HistoryEntryState>(Math.Min(history.Count + 1, limit)) { visit };
        List<HistoryEntryState> dropped = [];
        foreach (var entry in history) {
            if (entry.Id == visit.Id) continue;
            if (visited.Count == limit) dropped.Add(entry);
            else visited.Add(entry);
        }
        AddressIndex.Visited(history, visited, visit, previous, dropped);
        return visited;
    }

    /// The history with the newest entry for `url` titled `title`, in its
    /// place and with its visits as they were. Null for a blank title, an
    /// address history keeps no entry for, or an entry already titled so.
    internal static IReadOnlyList<HistoryEntryState>? Retitle(IReadOnlyList<HistoryEntryState> history, string url, string title) {
        ArgumentNullException.ThrowIfNull(history);
        if (string.IsNullOrEmpty(title) || new WebAddress(url).Normalized is not { } normalized
            || AddressIndex.Of(history).Entry(normalized) is not { } entry || entry.Title == title) return null;
        var retitled = entry with { Title = title };
        var edited = history.Select(existing => existing.Id == entry.Id ? retitled : existing).ToList();
        AddressIndex.Visited(history, edited, retitled, entry, []);
        return edited;
    }

    /// The entry a visit to `normalizedUrl` titled `title` leaves: `previous`
    /// with one more visit, or a new entry taking `newId`. A blank title is
    /// the page saying nothing, so the entry keeps its title, and a new one
    /// takes the address's host. `normalizedUrl` is an address in its normal
    /// form, and `previous`, when there is one, is its entry.
    internal static HistoryEntryState Record(string normalizedUrl, string? title, DateTimeOffset now, Guid newId, HistoryEntryState? previous) {
        if (new WebAddress(normalizedUrl).Normalized != normalizedUrl || newId == Guid.Empty
            || previous is not null && previous.Url != normalizedUrl)
            throw new ArgumentException("A visit is to an address in its normal form, with a new identity or the address's own entry.");
        string resolvedTitle = !string.IsNullOrEmpty(title) ? title : previous?.Title ?? new Uri(normalizedUrl).Host;
        if (resolvedTitle.Length == 0) resolvedTitle = normalizedUrl;
        return previous is null ? new(newId, normalizedUrl, resolvedTitle, now, now, 1)
            : previous with { Title = resolvedTitle, LastVisitedAt = now, VisitCount = checked(previous.VisitCount + 1) };
    }

    #endregion
}
