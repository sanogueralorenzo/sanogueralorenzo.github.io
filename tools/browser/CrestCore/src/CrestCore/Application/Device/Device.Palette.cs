using System.Collections.Immutable;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// What each persistent session's Spaces' palettes remember on this device: frecency from the visits its history records, what a person typed
/// or picked, and which row they picked for what they typed. The device store
/// keeps it when the device has one, and it never syncs. A private window's
/// palette remembers nothing. Clearing or removing history forgets the places
/// it held, and a deleted Space's memory goes with it.
internal sealed partial class Device {
    #region Static Variables

    /// A history entry first counts as a visit this palette saw when it was
    /// recorded no longer ago than this; older ones arrived from elsewhere.
    private static readonly TimeSpan FreshVisit = TimeSpan.FromMinutes(5);

    #endregion

    #region Variables

    /// Each persistent Space's palette memory.
    private ImmutableDictionary<Guid, PaletteMemory> paletteMemories = ImmutableDictionary<Guid, PaletteMemory>.Empty;

    #endregion

    #region Actions - Palette intents

    /// Runs one palette intent.
    public void Handle(PaletteIntent intent, DeviceTurn turn) => intent.Apply(this, turn);

    /// Remembers that a person in `windowId` picked `row` after typing `text`.
    internal void RecordPaletteChoice(Guid windowId, string text, PaletteRow row, DateTimeOffset now) {
        if (PersistentSpace(windowId) is not { } owner) return;
        var (space, preferences) = owner;
        var destination = row.Kind.Destination(row, TabAddress(space));
        if (destination is null) return;
        string? address = destination.Kind == PaletteDestinationKind.Address
            ? row.Address ?? (row.TabId is { } tab ? TabAddress(space)(tab) : null) : null;
        var before = address is not null && new WebAddress(address).Normalized is { } normalized
            ? AddressIndex.Of(space.History).Entry(normalized) : null;
        Remember(space.Id, now, memory => memory.Chose(text, destination, address, before, now, preferences.Palette.LearnsChoices));
    }

    /// Forgets the picks that led to `row` in the Space `windowId` shows.
    internal void ForgetPaletteChoices(Guid windowId, PaletteRow row) {
        if (PersistentSpace(windowId) is not { } owner || row.Kind.Destination(row, TabAddress(owner.Space)) is not { } destination) return;
        Remember(owner.Space.Id, null, memory => memory.Forgetting(destination));
    }

    /// Forgets what every palette learned.
    internal void ClearPaletteChoices() {
        lock (gate) {
            var cleared = paletteMemories.ToImmutableDictionary(entry => entry.Key, entry => entry.Value.Unlearned());
            if (cleared.All(entry => ReferenceEquals(entry.Value, paletteMemories[entry.Key]))) return;
            paletteMemories = cleared;
            storage?.EnqueueDevice(Records());
        }
    }

    #endregion

    #region Actions - Palette reading

    /// What the palette of `spaceId` remembers, or a memory that began after
    /// every entry of its history when it remembers nothing yet.
    internal PaletteMemory MemoryOf(Guid spaceId) {
        lock (gate) return paletteMemories.GetValueOrDefault(spaceId) ?? PaletteMemory.Starting(DateTimeOffset.MaxValue);
    }

    #endregion

    #region Actions - Palette remembering

    /// Remembers what a commit of the persistent session changed for its
    /// palettes: a new Space starts remembering, a fresh visit raises its
    /// page's frecency, history that lost entries forgets their places, and
    /// a deleted Space's memory goes. Called with no lock held.
    private void RememberPublished(Guid workspaceId, SessionState previous, SessionState next) {
        lock (gate) {
            if (workspaces.GetValueOrDefault(workspaceId)?.Kind.KeepsAppPreferences != true) return;
            var now = clock.Now;
            var memories = paletteMemories;
            bool remembered = false;
            foreach (var space in next.Spaces) {
                var known = memories.GetValueOrDefault(space.Id);
                var memory = known ?? PaletteMemory.Starting(now);
                if (previous.Spaces.FirstOrDefault(before => before.Id == space.Id) is { } before && !ReferenceEquals(before.History, space.History))
                    memory = Remembered(memory, before.History, space.History, now);
                if (ReferenceEquals(memory, known)) continue;
                memories = memories.SetItem(space.Id, memory);
                remembered |= known is not null || memory.Places.Count > 0 || memory.Choices.Count > 0;
            }
            foreach (var gone in previous.Spaces.Where(before => next.Spaces.All(space => space.Id != before.Id))) {
                remembered |= memories.ContainsKey(gone.Id);
                memories = memories.Remove(gone.Id);
            }
            if (ReferenceEquals(memories, paletteMemories)) return;
            paletteMemories = memories;
            // A memory that only began is saved with the first thing it remembers.
            if (remembered) storage?.EnqueueDevice(Records());
        }
    }

    /// `memory` after a Space's history went from `previous` to `next`.
    private static PaletteMemory Remembered(PaletteMemory memory, IReadOnlyList<HistoryEntryState> previous,
        IReadOnlyList<HistoryEntryState> next, DateTimeOffset now) {
        if (next.Count > 0) {
            var visit = next[0];
            var before = AddressIndex.Of(previous).Entry(visit.Url);
            if ((before is null || visit.LastVisitedAt > before.LastVisitedAt) && now - visit.LastVisitedAt <= FreshVisit)
                memory = memory.Visited(visit.Url, before, visit.LastVisitedAt);
        }
        if (next.Count >= previous.Count) return memory;
        var places = next.Select(entry => PaletteMemory.Place(entry.Url)).OfType<string>().ToHashSet(StringComparer.Ordinal);
        return memory.Keeping(places, now);
    }

    /// Keeps `revise`'s memory for `spaceId`, starting one at `now` when it has
    /// none, or leaving it be when it has none and no time is given.
    private void Remember(Guid spaceId, DateTimeOffset? now, Func<PaletteMemory, PaletteMemory> revise) {
        lock (gate) {
            var memory = paletteMemories.GetValueOrDefault(spaceId) ?? (now is { } started ? PaletteMemory.Starting(started) : null);
            if (memory is null) return;
            var revised = revise(memory);
            if (paletteMemories.TryGetValue(spaceId, out var kept) && ReferenceEquals(kept, revised)) return;
            paletteMemories = paletteMemories.SetItem(spaceId, revised);
            storage?.EnqueueDevice(Records());
        }
    }

    /// The Space window `windowId` shows and the device's preferences, when
    /// that Space belongs to a persistent session, which keeps what it
    /// learns; null for a private or borrowed window. Called with no lock held.
    private (SpaceState Space, AppPreferences Preferences)? PersistentSpace(Guid windowId) {
        if (Showing(windowId, null) is not { } shown || Attached(shown.WorkspaceId) is not { Kind.KeepsAppPreferences: true } authority)
            return null;
        var state = authority.Current;
        return state?.Spaces.FirstOrDefault(space => space.Id == shown.SpaceId) is { } space ? (space, state.AppPreferences ?? AppPreferences.Default) : null;
    }

    /// Reads the address a tab of `space` shows or keeps.
    private static Func<Guid, string?> TabAddress(SpaceState space) =>
        tab => space.Tabs.FirstOrDefault(candidate => candidate.Id == tab) is { } found ? found.SavedAddress ?? found.Url : null;

    #endregion
}
