using System.Collections.Immutable;
using System.Runtime.CompilerServices;

using CrestCore.Contracts;

namespace CrestCore.Domain;

/// What a Space's history knows by address, kept beside the history list it
/// describes: each address's newest entry, which a visit reads instead of
/// scanning the history. A visit derives the next list's index from its
/// list's; any other edit leaves a new list whose index is made when it is
/// first read. Indexes are immutable, so any thread may read one.
public sealed class AddressIndex {
    #region Static Variables

    private static readonly ConditionalWeakTable<IReadOnlyList<HistoryEntryState>, AddressIndex> Indexes = [];

    #endregion

    #region Variables

    /// The newest entry for each address.
    private readonly ImmutableDictionary<string, HistoryEntryState> entries;

    #endregion

    #region Constructors

    private AddressIndex(ImmutableDictionary<string, HistoryEntryState> entries) {
        this.entries = entries;
    }

    #endregion

    #region Actions - Reading

    /// The index of `history`, made now when no visit derived it.
    public static AddressIndex Of(IReadOnlyList<HistoryEntryState> history) {
        ArgumentNullException.ThrowIfNull(history);
        return Indexes.GetValue(history, Made);
    }

    /// The newest entry for `normalizedUrl`, or null.
    public HistoryEntryState? Entry(string normalizedUrl) => entries.GetValueOrDefault(normalizedUrl);

    private static AddressIndex Made(IReadOnlyList<HistoryEntryState> history) {
        var entries = ImmutableDictionary.CreateBuilder<string, HistoryEntryState>(StringComparer.Ordinal);
        foreach (var entry in history) entries.TryAdd(entry.Url, entry);
        return new(entries.ToImmutable());
    }

    #endregion

    #region Actions - Visits

    /// Records that `visited` is `history` after a visit that put `visit`
    /// first, in place of `replaced` when the address was already known, and
    /// left out `dropped` to stay within the history's limit. An index made for
    /// `history` becomes `visited`'s with only those entries changed; without
    /// one, `visited`'s is made when first read.
    public static void Visited(IReadOnlyList<HistoryEntryState> history, IReadOnlyList<HistoryEntryState> visited,
        HistoryEntryState visit, HistoryEntryState? replaced, IReadOnlyList<HistoryEntryState> dropped) {
        ArgumentNullException.ThrowIfNull(visit);
        ArgumentNullException.ThrowIfNull(dropped);
        if (!Indexes.TryGetValue(history, out var index)) return;
        var entries = index.entries.ToBuilder();
        foreach (var gone in dropped.Append(replaced).OfType<HistoryEntryState>()) {
            if (entries.TryGetValue(gone.Url, out var newest) && newest.Id == gone.Id) entries.Remove(gone.Url);
        }
        entries[visit.Url] = visit;
        var next = new AddressIndex(entries.ToImmutable());
#if CREST_CROSS_CHECKS
        if (!next.Describes(visited))
            throw new System.Diagnostics.UnreachableException("An address index derived from a visit differs from the one its history makes.");
#endif
        Indexes.AddOrUpdate(visited, next);
    }

#if CREST_CROSS_CHECKS
    /// Whether this index holds exactly what one made from `history` holds:
    /// each address's newest entry.
    private bool Describes(IReadOnlyList<HistoryEntryState> history) {
        var newest = new Dictionary<string, HistoryEntryState>(StringComparer.Ordinal);
        foreach (var entry in history) newest.TryAdd(entry.Url, entry);
        if (entries.Count != newest.Count || entries.Any(pair => !newest.TryGetValue(pair.Key, out var entry) || entry != pair.Value))
            return false;
        return true;
    }
#endif

    #endregion
}
