using System.Collections.Immutable;
using System.Runtime.CompilerServices;

using CrestCore.Contracts;

namespace CrestCore.Domain;

/// What a Space's history knows by address, kept beside the history list it
/// describes: each address's newest entry, which a visit reads instead of
/// scanning the history, and each entry taken apart for completing addresses,
/// which is made on first use. A visit derives the next list's index from its
/// list's; any other edit leaves a new list whose index is made when it is
/// first read. Indexes are immutable, so any thread may read one.
public sealed class AddressIndex {
    #region Static Variables

    private static readonly ConditionalWeakTable<IReadOnlyList<HistoryEntryState>, AddressIndex> Indexes = [];

    #endregion

    #region Variables

    /// The newest entry for each address.
    private readonly ImmutableDictionary<string, HistoryEntryState> entries;
    /// Each entry taken apart for completion, by its identity; null until
    /// completion first reads it.
    private ImmutableDictionary<Guid, AddressCandidate>? candidates;
    private readonly IReadOnlyList<HistoryEntryState>? history;

    #endregion

    #region Constructors

    private AddressIndex(ImmutableDictionary<string, HistoryEntryState> entries, ImmutableDictionary<Guid, AddressCandidate>? candidates,
        IReadOnlyList<HistoryEntryState>? history) {
        this.entries = entries;
        this.candidates = candidates;
        this.history = history;
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

    /// Every entry taken apart for completing addresses.
    public IEnumerable<AddressCandidate> Candidates() {
        if (candidates is { } made) return made.Values;
        var built = ImmutableDictionary.CreateBuilder<Guid, AddressCandidate>();
        foreach (var entry in history ?? []) Add(built, entry);
        candidates = built.ToImmutable();
        return candidates.Values;
    }

    private static AddressIndex Made(IReadOnlyList<HistoryEntryState> history) {
        var entries = ImmutableDictionary.CreateBuilder<string, HistoryEntryState>(StringComparer.Ordinal);
        foreach (var entry in history) entries.TryAdd(entry.Url, entry);
        return new(entries.ToImmutable(), null, history);
    }

    private static void Add(ImmutableDictionary<Guid, AddressCandidate>.Builder candidates, HistoryEntryState entry) {
        if (AddressCandidate.Of(entry.Url, AddressCandidate.HistorySource, entry.LastVisitedAt, entry.VisitCount, entry.FirstVisitedAt)
            is { } candidate)
            candidates[entry.Id] = candidate;
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
        var candidates = index.candidates?.ToBuilder();
        foreach (var gone in dropped.Append(replaced).OfType<HistoryEntryState>()) {
            if (entries.TryGetValue(gone.Url, out var newest) && newest.Id == gone.Id) entries.Remove(gone.Url);
            candidates?.Remove(gone.Id);
        }
        entries[visit.Url] = visit;
        if (candidates is not null) Add(candidates, visit);
        var next = new AddressIndex(entries.ToImmutable(), candidates?.ToImmutable(), visited);
#if CREST_CROSS_CHECKS
        if (!next.Describes(visited))
            throw new System.Diagnostics.UnreachableException("An address index derived from a visit differs from the one its history makes.");
#endif
        Indexes.AddOrUpdate(visited, next);
    }

#if CREST_CROSS_CHECKS
    /// Whether this index holds exactly what one made from `history` holds:
    /// each address's newest entry, and a candidate for every entry that
    /// makes one, carrying that entry's values.
    private bool Describes(IReadOnlyList<HistoryEntryState> history) {
        var newest = new Dictionary<string, HistoryEntryState>(StringComparer.Ordinal);
        foreach (var entry in history) newest.TryAdd(entry.Url, entry);
        if (entries.Count != newest.Count || entries.Any(pair => !newest.TryGetValue(pair.Key, out var entry) || entry != pair.Value))
            return false;
        if (candidates is not { } own) return true;
        int counted = 0;
        foreach (var entry in history) {
            if (own.TryGetValue(entry.Id, out var candidate)) {
                counted++;
                if (candidate.Url != entry.Url || candidate.Date != entry.LastVisitedAt
                    || candidate.Visits != Math.Min(AddressCandidate.MaximumCountedVisits, entry.VisitCount)) return false;
            } else if (AddressCandidate.Of(entry.Url, AddressCandidate.HistorySource, entry.LastVisitedAt, entry.VisitCount) is not null)
                return false;
        }
        return counted == own.Count;
    }
#endif

    #endregion
}
