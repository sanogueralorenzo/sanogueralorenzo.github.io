using CrestCore.Contracts;

namespace CrestCore.Application;

/// A WebKit page's bounded back and forward history. Cold entries remain
/// available after a renderer is released, even when native state cannot restore.
internal sealed partial class PageHistory {
    #region Types

    /// One engine's stretch of the page's history.
    private sealed class Run {
        /// The run's entries, oldest first, and the index of the one its
        /// engine shows, or showed when the page left it.
        public List<PageHistoryEntry> Entries { get; set; } = [];
        public int Current { get; set; } = -1;

        /// The first and last entries that belong to the run. Entries its
        /// engine holds before or past them belong to other runs.
        public Guid? Start { get; set; }
        public Guid? Boundary { get; set; }

        public bool Holds(Guid entryId) => Entries.Any(entry => entry.Id == entryId);

        public Run Slice(int from, int to) => new() {
            Entries = Entries[from..to],
            Current = Current >= from && Current < to ? Current - from : to - from - 1,
            Start = Entries[from].Id,
            Boundary = Entries[to - 1].Id,
        };
    }

    /// A page returning to a run its engine restores: the entry it goes to,
    /// the identities the restored history held when the page left it, and
    /// the entry the engine showed on restoring, until it moves off it.
    private sealed record Arrival(Run Run, Guid Entry, IReadOnlyList<Guid> Native, Guid? Restored = null);

    #endregion

    #region Static Variables

    /// The most entries a page's history holds, as WebKit keeps them.
    public const int Capacity = 100;

    #endregion

    #region Variables

    private readonly List<Run> runs = [];

    /// The index of the live run, or -1 before an engine reported one.
    private int live = -1;

    /// The identities the page's engine holds now, in order, as it last
    /// reported them.
    private List<Guid> native = [];

    private Arrival? arriving;

    /// The entry the core asked the page's engine to go to, until a report
    /// shows the engine reached it or went elsewhere.
    private Guid? going;

    /// Every entry, oldest first.
    public IReadOnlyList<PageHistoryEntry> Entries => [.. runs.SelectMany(run => run.Entries)];

    /// The index of the entry the page shows in `Entries`, or -1.
    public int Current =>
        live < 0 || runs[live].Current < 0 ? -1 : runs.Take(live).Sum(run => run.Entries.Count) + runs[live].Current;

    /// The entry the page shows, or null.
    public PageHistoryEntry? Shown => Current >= 0 ? Entries[Current] : null;

    public bool CanGoBack => Current > 0;
    public bool CanGoForward => Current >= 0 && Current < Entries.Count - 1;

    /// The entries the page can go back to, nearest first.
    public IReadOnlyList<PageHistoryEntry> Back => [.. Entries.Take(Math.Max(Current, 0)).Reverse()];

    /// The entries the page can go forward to, nearest first. A page that
    /// shows no entry yet, as one that has not committed, has none.
    public IReadOnlyList<PageHistoryEntry> Forward => Current < 0 ? [] : [.. Entries.Skip(Current + 1)];

    #endregion

    #region Actions - Reports

    /// Whether an engine could report `entries` with `current` shown: no more
    /// than `Capacity`, no entry twice, and a current entry inside the list.
    /// Only an empty history has no current entry.
    public static bool Holds(IReadOnlyList<PageHistoryEntry> entries, int current) {
        bool fits = entries.Count == 0 ? current == -1 : current >= 0 && current < entries.Count;
        return fits && entries.Count <= Capacity && entries.Select(entry => entry.Id).Distinct().Count() == entries.Count;
    }

    /// WebKit reported `entries` with `current` shown. Answers the entry the engine should go to now: the one a page
    /// returning to a restored run asked for, once that history arrived.
    public Guid? Report(IReadOnlyList<PageHistoryEntry> entries, int current) {
        // A page that committed nothing yet holds no history: the runs stay
        // as they are until its engine reports one.
        if (entries.Count == 0) {
            native = [];
            return null;
        }
        if (live < 0) {
            runs.Add(new Run());
            live = runs.Count - 1;
        }
        var reported = entries.ToList();
        Guid? shown = current >= 0 ? reported[current].Id : null;
        Guid? target = null;
        // The engine reached the entry, went somewhere new, or no longer holds
        // the entry it was asked to go to, as when it refused to.
        if (going is { } asked && (shown == asked || shown is { } reached && !runs.Any(run => run.Holds(reached))
                || native.Contains(asked) && !reported.Any(entry => entry.Id == asked)))
            going = null;
        // A restored engine first shows the entry it showed when the page
        // left it. Until it moves off that entry the page is still arriving,
        // and shows the entry it returned for.
        bool restoring = arriving is { } waiting && ReferenceEquals(waiting.Run, runs[live])
            && (waiting.Restored is null || waiting.Restored == shown);
        if (restoring) {
            var arrival = arriving!;
            var entry = arrival.Entry;
            bool restored = true;
            if (arrival.Restored is null && reported.Count > 0) {
                restored = Rename(arrival.Native, reported, ref entry);
                target = entry;
            }
            arriving = shown == entry ? null : arrival with { Entry = entry, Restored = shown };
            if (!restored) {
                Recover(entry);
                restoring = false;
                target = null;
            }
        } else {
            arriving = null;
            // An entry another run of this engine holds, reached natively,
            // makes that run live.
            if (shown is { } id && !runs[live].Holds(id)
                && runs.FindIndex(run => run.Holds(id)) is var other and >= 0)
                live = other;
        }
        var run = runs[live];
        int from = run.Start is { } start && reported.FindIndex(entry => entry.Id == start) is var first and >= 0 ? first : 0;
        int to = reported.Count - 1;
        if (run.Boundary is { } boundary && reported.FindIndex(entry => entry.Id == boundary) is var last and >= 0) to = last;
        if (!restoring && current > to) {
            // A navigation past the run's last entry leaves no forward
            // history behind it, in cold slices as well.
            run.Boundary = null;
            to = reported.Count - 1;
            DropAfter(live);
        }
        if (!restoring && current >= 0 && current < from) {
            run.Start = null;
            from = 0;
        }
        int anchor = Math.Clamp(current, from, to);
        if (arriving is { } still && reported.FindIndex(entry => entry.Id == still.Entry) is var arrived && arrived >= from && arrived <= to)
            anchor = arrived;
        // The run never takes in an entry another run holds, which its
        // engine still keeps from an earlier stretch.
        for (int index = anchor - 1; index >= from; index--)
            if (Foreign(run, reported[index].Id)) {
                from = index + 1;
                break;
            }
        for (int index = anchor + 1; index <= to; index++)
            if (Foreign(run, reported[index].Id)) {
                to = index - 1;
                break;
            }
        var slice = reported.Count == 0 ? [] : reported[from..(to + 1)];
        int at = anchor - from;
        // A new entry the run did not hold is a new navigation, which leaves
        // no forward history behind it, in cold slices as well.
        // A run's first report is where it begins, not a navigation.
        if (!restoring && slice.Count > 0 && run.Entries.Count > 0 && !run.Holds(slice[at].Id)) DropAfter(live);
        run.Entries = slice;
        run.Current = slice.Count == 0 ? -1 : at;
        native = [.. reported.Select(entry => entry.Id)];
        Trim();
        return target is { } go && slice.Any(entry => entry.Id == go) && go != shown ? go : null;
    }

    /// Whether a run other than `run` holds the entry `entryId` names.
    private bool Foreign(Run run, Guid entryId) => runs.Any(other => !ReferenceEquals(other, run) && other.Holds(entryId));

    /// Whether the engine brought back the history it kept, whose
    /// identities were `kept`, in order. A restored engine may give the
    /// entries new identities, as WebKit does: every run of that engine then
    /// takes the engine's identities by position, so the engine finds every
    /// entry the core asks for, and `target` is what the entry is called now.
    /// A history of another length, or whose addresses differ, is not the one
    /// the engine kept.
    private bool Rename(IReadOnlyList<Guid> kept, List<PageHistoryEntry> reported, ref Guid target) {
        var goal = target;
        if (kept.All(id => reported.Any(entry => entry.Id == id))) return reported.Any(entry => entry.Id == goal);
        if (kept.Count != reported.Count) return false;
        for (int index = 0; index < kept.Count; index++)
            if (Entry(kept[index]) is { } known && !new WebAddress(known.Url).IsSamePage(new WebAddress(reported[index].Url)))
                return false;
        var renamed = new Dictionary<Guid, Guid>();
        for (int index = 0; index < kept.Count; index++) renamed[kept[index]] = reported[index].Id;
        Guid Of(Guid id) => renamed.GetValueOrDefault(id, id);
        foreach (var run in runs) {
            run.Entries = [.. run.Entries.Select(entry => entry with { Id = Of(entry.Id) })];
            run.Start = run.Start is { } start ? Of(start) : null;
            run.Boundary = run.Boundary is { } boundary ? Of(boundary) : null;
        }
        target = Of(target);
        return reported.Any(entry => entry.Id == goal) || renamed.ContainsKey(goal);
    }

    /// The engine the page returned to did not bring back the history it
    /// kept, and loaded afresh instead. The run the page returned to keeps
    /// its entries, which load afresh when reached; the entry it returned
    /// for goes with what the engine shows now, which begins a run of its
    /// own.
    private void Recover(Guid entryId) {
        var run = runs[live];
        run.Current = run.Entries.FindIndex(entry => entry.Id == entryId) is var at and >= 0 ? at : run.Current;
        arriving = null;
        Leave(Entry(entryId)?.Url);
    }

    /// Drops every run after `index`: a new navigation leaves no forward
    /// history behind it.
    private void DropAfter(int index) {
        if (index + 1 < runs.Count) runs.RemoveRange(index + 1, runs.Count - index - 1);
    }

    /// Keeps the history to `Capacity` entries, dropping the oldest first.
    /// A run that lost its first entries starts at the first it keeps, so
    /// they do not come back when its engine reports them.
    private void Trim() {
        while (runs.Sum(run => run.Entries.Count) > Capacity) {
            var oldest = runs[0];
            if (live == 0 && oldest.Current <= 0) return;
            if (oldest.Entries.Count == 0) {
                runs.RemoveAt(0);
                live--;
                continue;
            }
            oldest.Entries.RemoveAt(0);
            // A run the page left on the entry it drops returns to the first
            // entry it keeps.
            oldest.Current = oldest.Entries.Count == 0 ? -1 : Math.Max(oldest.Current - 1, 0);
            if (oldest.Entries.Count > 0) {
                oldest.Start = oldest.Entries[0].Id;
            } else if (live > 0) {
                runs.RemoveAt(0);
                live--;
            }
        }
    }

    #endregion

    #region Actions - Engines

    /// A reopened renderer loads the current address afresh. Keep the earlier
    /// and later entries as cold slices surrounding its new native history.
    private void Leave(string? address) {
        int at = runs.Count;
        if (live >= 0) {
            var run = runs[live];
            bool moves = address is not null && run.Current >= 0
                && new WebAddress(run.Entries[run.Current].Url).IsSamePage(new WebAddress(address));
            if (!moves) DropAfter(live);
            if (run.Current >= 0) {
                if (moves && run.Current + 1 < run.Entries.Count) runs.Insert(live + 1, run.Slice(run.Current + 1, run.Entries.Count));
                int keep = moves ? run.Current : run.Current + 1;
                run.Entries = run.Entries[..keep];
                run.Current = keep - 1;
            }
            at = live + 1;
            if (run.Entries.Count == 0) {
                runs.RemoveAt(live);
                at = live;
            } else {
                run.Boundary = run.Entries[^1].Id;
            }
        }
        var arrival = new Run();
        runs.Insert(at, arrival);
        Arrive(arrival, at);
    }

    /// The page goes to the entry `entryId` names, which its engine no longer
    /// holds, by loading it afresh on its own engine. The engine drops what
    /// lay ahead of the entry it shows, which loads afresh too from then on.
    public PageHistoryEntry Load(Guid entryId) {
        var run = runs[live];
        if (run.Current >= 0 && run.Current + 1 < run.Entries.Count) {
            var ahead = run.Slice(run.Current + 1, run.Entries.Count);
            run.Entries = run.Entries[..(run.Current + 1)];
            run.Boundary = run.Entries[^1].Id;
            runs.Insert(live + 1, ahead);
        } else if (run.Current >= 0) {
            run.Boundary = run.Entries[^1].Id;
        }
        var held = native;
        var entry = Split(runs.FindIndex(each => each.Holds(entryId)), entryId);
        runs[live].Start = entryId;
        native = held;
        going = entryId;
        return entry;
    }

    /// Splits the run at `index` around the entry `entryId` names, which
    /// becomes a live run of its own, to load afresh; the entries
    /// around it stay, and load afresh when reached. Answers the entry.
    private PageHistoryEntry Split(int index, Guid entryId) {
        var target = runs[index];
        int at = target.Entries.FindIndex(entry => entry.Id == entryId);
        var entry = target.Entries[at];
        var parts = new List<Run>();
        if (at > 0) parts.Add(target.Slice(0, at));
        var arrival = new Run() { Entries = [entry], Current = 0 };
        parts.Add(arrival);
        if (at + 1 < target.Entries.Count) parts.Add(target.Slice(at + 1, target.Entries.Count));
        runs.RemoveAt(index);
        runs.InsertRange(index, parts);
        Arrive(arrival, runs.IndexOf(arrival));
        return entry;
    }

    /// `run`, at `index` in the line, becomes live on an engine page that
    /// holds no history yet.
    private void Arrive(Run run, int index) {
        if (index == runs.Count) runs.Add(run);
        live = index;
        native = [];
        arriving = null;
        going = null;
    }

    /// A reopened tab restores native identities by position. Without usable
    /// native state, its current entry loads afresh and older entries stay cold.
    public void Reopen(bool restores) {
        if (live >= 0 && restores && runs[live].Current >= 0) {
            arriving = new Arrival(runs[live], runs[live].Entries[runs[live].Current].Id, native);
            native = [];
        } else {
            Leave(Shown?.Url);
        }
    }

    #endregion

    #region Actions - Traversal

    /// The core asks the page's engine to go to the entry `entryId` names,
    /// which it holds.
    public void Go(Guid entryId) => going = entryId;

    /// The entry `offset` steps from the current one, back when negative, or
    /// null when the history has none there.
    public PageHistoryEntry? Step(int offset) {
        int current = Current;
        int index = current + offset;
        var entries = Entries;
        return offset != 0 && current >= 0 && index >= 0 && index < entries.Count ? entries[index] : null;
    }

    /// Whether the history holds the entry `entryId` names, other than the
    /// current one.
    public bool Reaches(Guid entryId) {
        int current = Current;
        return current >= 0 && Entries.Where((entry, index) => index != current).Any(entry => entry.Id == entryId);
    }

    /// Whether the page's engine holds the entry `entryId` names now, so it
    /// goes there itself.
    public bool Holds(Guid entryId) =>
        live >= 0 && native.Contains(entryId) && runs.Any(run => run.Holds(entryId));

    /// The entry `entryId` names, or null.
    public PageHistoryEntry? Entry(Guid entryId) => Entries.FirstOrDefault(entry => entry.Id == entryId);

    #endregion
}
