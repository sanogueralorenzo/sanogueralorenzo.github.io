using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// A visit reads the address index instead of scanning the history, and
/// derives the next index from the last. Both must answer exactly what a scan
/// and an index made from scratch answer, or history would silently double or
/// lose entries.
public sealed class AddressIndexTests {
    /// The visit as it was before the index: a scan for the address's newest
    /// entry, which the visit replaces at the front, within the limit.
    /// A history limit small enough to cross many times in a test; the walk
    /// is the same at the real limit.
    private const int Limit = 300;

    private static IReadOnlyList<HistoryEntryState> Scanned(IReadOnlyList<HistoryEntryState> history, string url, string title,
        DateTimeOffset now, Guid id) {
        string normalized = new WebAddress(url).Normalized!;
        var previous = history.FirstOrDefault(entry => entry.Url == normalized);
        var visit = HistoryEntryState.Record(normalized, title, now, id, previous);
        var visited = new List<HistoryEntryState> { visit };
        foreach (var entry in history) {
            if (visited.Count == Limit) break;
            if (entry.Id != visit.Id) visited.Add(entry);
        }
        return visited;
    }

    /// Whether `index` answers what an index made from scratch for the same
    /// entries answers, for every address and completion candidate.
    private static void AssertMatchesAFreshIndex(IReadOnlyList<HistoryEntryState> history) {
        var derived = AddressIndex.Of(history);
        var fresh = AddressIndex.Of([.. history]);
        foreach (var url in history.Select(entry => entry.Url).Distinct()) Assert.Equal(fresh.Entry(url), derived.Entry(url));
        Assert.Equal(fresh.Candidates().Select(candidate => (candidate.Url, candidate.Visits, candidate.Date)).OrderBy(value => value.Url),
            derived.Candidates().Select(candidate => (candidate.Url, candidate.Visits, candidate.Date)).OrderBy(value => value.Url));
    }

    [Fact]
    public void VisitsThroughTheIndexMatchAScanPastTheHistoryLimit() {
        var random = new Random(264);
        var start = DateTimeOffset.Parse("2026-09-25T00:00:00Z", System.Globalization.CultureInfo.InvariantCulture);
        IReadOnlyList<HistoryEntryState> history = [];
        IReadOnlyList<HistoryEntryState> scanned = [];
        int visits = Limit * 4;
        for (int visit = 0; visit < visits; visit++) {
            // Mostly new addresses, often a return to one visited before, and
            // sometimes a fragment of one, which is the same page.
            int page = random.Next(4) == 0 ? random.Next(Math.Max(1, visit)) : visit;
            string url = $"https://site{page % 97}.example/page/{page}" + (random.Next(5) == 0 ? "#part" : "");
            var now = start.AddSeconds(visit);
            var id = Guid.NewGuid();
            var next = HistoryEntryState.Visit(history, url, $"Page {page}", now, id, Limit)!;
            scanned = Scanned(scanned, url, $"Page {page}", now, id);
            Assert.True(scanned.SequenceEqual(next), $"Visit {visit} differs from a scan.");
            // Completion candidates join the index just before the limit is
            // reached, so derivation carries them past it.
            if (history.Count == Limit - 20) _ = AddressIndex.Of(next).Candidates();
            if (visit % 50 == 0 || Math.Abs(next.Count - Limit) <= 2 || visit == visits - 1)
                AssertMatchesAFreshIndex(next);
            history = next;
        }
        Assert.Equal(Limit, history.Count);
    }
}
