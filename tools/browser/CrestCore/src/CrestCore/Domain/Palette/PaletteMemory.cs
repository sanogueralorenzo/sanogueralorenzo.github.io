using System.Collections.Immutable;

using CrestCore.Contracts;

namespace CrestCore.Domain;

#region Types

/// How a place a Space knows was used: `DecayDay` is the day, counted from the
/// Unix epoch, on which its frecency would fall to one, and `TypedAt` is the
/// last time a person typed or picked it in the palette, or null.
public sealed record PlaceUse(double DecayDay, DateTimeOffset? TypedAt);

/// A row a person picked after typing `Text`: where it led, how often they
/// picked it there, decayed to `LastUsedAt`, and when they last did.
public sealed record PaletteChoice(string Text, PaletteDestination Destination, double Uses, DateTimeOffset LastUsedAt);

#endregion

/// What one Space's palette remembers on this device, which it never syncs:
/// how often and recently each place was used, as frecency, whether a person
/// typed or picked it, and which row they picked for what they typed. A
/// visit adds one to a place's frecency and typing or picking it adds one
/// more, so a typed visit counts twice a link click, and older use halves
/// every 30 days. Picks decay too, and are forgotten after 90 days unused.
/// `Since` is when the Space began remembering: history older than that
/// carries no record of what was typed. Memories are immutable.
public sealed class PaletteMemory {
    #region Static Variables

    /// Days over which a place's frecency halves.
    public const double HalfLifeDays = 30;

    /// The most picks a Space remembers; the least recent go first.
    public const int MaximumChoices = 1_000;

    /// The most places a Space remembers; the least used go first.
    public const int MaximumPlaces = 5_000;

    /// How long a pick nobody repeats is remembered, and how long a typed
    /// place may be completed inline.
    public static readonly TimeSpan Lifetime = TimeSpan.FromDays(90);

    /// The longest typed text a pick remembers.
    private const int MaximumTextLength = 64;

    /// Each day a pick goes unused keeps this share of its uses.
    private const double DailyChoiceDecay = 0.975;

    /// A repeated pick keeps this share of its earlier uses, plus one.
    private const double ChoiceCarry = 0.9;

    #endregion

    #region Variables

    /// When the Space began remembering.
    public DateTimeOffset Since { get; }

    /// Each place the Space remembers using, by its place key.
    public ImmutableDictionary<string, PlaceUse> Places { get; }

    /// The picks the Space remembers, least recent first.
    public ImmutableList<PaletteChoice> Choices { get; }

    /// The last time each host was typed or picked, made on first use.
    private ImmutableDictionary<string, DateTimeOffset>? typedHosts;

    #endregion

    #region Constructors

    public PaletteMemory(DateTimeOffset since, ImmutableDictionary<string, PlaceUse> places, ImmutableList<PaletteChoice> choices) {
        ArgumentNullException.ThrowIfNull(places);
        ArgumentNullException.ThrowIfNull(choices);
        Since = since;
        Places = places;
        Choices = choices;
    }

    /// A memory that begins at `since` and remembers nothing yet.
    public static PaletteMemory Starting(DateTimeOffset since) =>
        new(since, ImmutableDictionary<string, PlaceUse>.Empty.WithComparers(StringComparer.Ordinal), []);

    #endregion

    #region Actions - Reading

    /// The frecency of `url` at `now`: its remembered use, or for a place
    /// used only before the Space began remembering, its history's visits as
    /// if each happened on its last visit.
    public double Frecency(string url, HistoryEntryState? entry, DateTimeOffset now) {
        if (Place(url) is { } key && Places.TryGetValue(key, out var use)) return Score(use.DecayDay, Day(now));
        if (entry is null) return 0;
        return Math.Max(1, entry.VisitCount) * Math.Pow(2, -(Day(now) - Day(entry.LastVisitedAt)) / HalfLifeDays);
    }

    /// Whether a person typed or picked a page on `host` within the lifetime.
    public bool WasTyped(string host, DateTimeOffset now) {
        typedHosts ??= TypedHosts();
        return typedHosts.TryGetValue(WithoutWww(host.ToLowerInvariant()), out var typed) && now - typed <= Lifetime;
    }

    /// The boost the palette gives `destination` for `typed`: the strongest of
    /// the picks whose text starts with what was typed, by how often it was
    /// picked and how much of its text was typed, doubled when it was exactly
    /// this text. Zero when nothing learned matches.
    public double Learned(string typed, PaletteDestination destination, DateTimeOffset now) {
        string text = Folded(typed);
        if (text.Length == 0) return 0;
        double best = 0;
        foreach (var choice in Choices) {
            if (choice.Destination != destination || !choice.Text.StartsWith(text, StringComparison.Ordinal)) continue;
            double uses = Current(choice, now);
            double coverage = (double)text.Length / choice.Text.Length;
            double boost = 500 * uses / (uses + 1) * coverage * (choice.Text.Length == text.Length ? 2 : 1);
            best = Math.Max(best, boost);
        }
        return best;
    }

    /// The destination a person picked at least twice for exactly `typed`,
    /// the most used first, or null.
    public PaletteDestination? Habit(string typed, DateTimeOffset now) {
        string text = Folded(typed);
        return Choices.Where(choice => choice.Text == text && Current(choice, now) >= 1.8)
            .OrderByDescending(choice => Current(choice, now)).FirstOrDefault()?.Destination;
    }

    #endregion

    #region Actions - Remembering

    /// The memory after a visit to `url` at `at`.
    public PaletteMemory Visited(string url, HistoryEntryState? before, DateTimeOffset at) => Used(url, before, at, typed: false);

    /// The memory after a person picked `destination` for `typed` at `at`,
    /// typing or picking its address `address` when it has one. Without
    /// `learns`, only the address's use is remembered.
    public PaletteMemory Chose(string typed, PaletteDestination destination, string? address, HistoryEntryState? before,
        DateTimeOffset at, bool learns) {
        var memory = address is null ? this : Used(address, before, at, typed: true);
        string text = Folded(typed);
        if (!learns || text.Length == 0) return memory;
        if (text.Length > MaximumTextLength) text = text[..MaximumTextLength];
        int index = memory.Choices.FindIndex(choice => choice.Text == text && choice.Destination == destination);
        double uses = index < 0 ? 1 : ChoiceCarry * Current(memory.Choices[index], at) + 1;
        var choices = (index < 0 ? memory.Choices : memory.Choices.RemoveAt(index)).Add(new(text, destination, uses, at));
        if (choices.Count > MaximumChoices) choices = choices.RemoveRange(0, choices.Count - MaximumChoices);
        return new(memory.Since, memory.Places, choices);
    }

    /// The memory without the picks that led to `destination`.
    public PaletteMemory Forgetting(PaletteDestination destination) {
        var choices = Choices.RemoveAll(choice => choice.Destination == destination);
        return choices.Count == Choices.Count ? this : new(Since, Places, choices);
    }

    /// The memory with only the places `known` still holds, and only the
    /// picks that lead to one of them or to something other than a place;
    /// picks unused for the lifetime are forgotten too.
    public PaletteMemory Keeping(IReadOnlySet<string> known, DateTimeOffset now) {
        var places = Places.Where(place => known.Contains(place.Key)).ToImmutableDictionary(StringComparer.Ordinal);
        var choices = Choices.RemoveAll(choice => now - choice.LastUsedAt > Lifetime
            || choice.Destination.Kind == PaletteDestinationKind.Address && !known.Contains(choice.Destination.Value));
        return places.Count == Places.Count && choices.Count == Choices.Count ? this : new(Since, places, choices);
    }

    /// The memory with nothing learned: no picks and no typed places, its
    /// places' frecency kept.
    public PaletteMemory Unlearned() => new(Since,
        Places.ToImmutableDictionary(place => place.Key, place => place.Value with { TypedAt = null }, StringComparer.Ordinal), []);

    private PaletteMemory Used(string url, HistoryEntryState? before, DateTimeOffset at, bool typed) {
        if (Place(url) is not { } key) return this;
        double today = Day(at);
        double score = (Places.TryGetValue(key, out var use) ? Score(use.DecayDay, today) : Frecency(url, before, at)) + 1;
        var updated = new PlaceUse(today + HalfLifeDays * Math.Log2(score), typed ? at : use?.TypedAt);
        var places = Places.SetItem(key, updated);
        if (places.Count > MaximumPlaces)
            places = places.Remove(places.Where(place => place.Key != key).MinBy(place => place.Value.DecayDay).Key);
        return new(Since, places, Choices);
    }

    #endregion

    #region Actions - Places

    /// The key the palette knows a page by: its host without `www.` and in
    /// lower case, its port, path and query, without scheme or fragment.
    /// Null for an address that is not http or https.
    public static string? Place(string url) {
        ArgumentNullException.ThrowIfNull(url);
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || WebScheme.Named(uri.Scheme) is null || uri.Host.Length == 0) return null;
        string host = WithoutWww(uri.Host.ToLowerInvariant());
        string port = uri.IsDefaultPort ? "" : $":{uri.Port}";
        string path = uri.AbsolutePath == "/" ? "" : uri.AbsolutePath;
        return host + port + path + uri.Query;
    }

    /// `host` without a leading `www.`.
    public static string WithoutWww(string host) => host.StartsWith("www.", StringComparison.Ordinal) ? host[4..] : host;

    #endregion

    #region Actions - Support

    private ImmutableDictionary<string, DateTimeOffset> TypedHosts() {
        var hosts = ImmutableDictionary.CreateBuilder<string, DateTimeOffset>(StringComparer.Ordinal);
        foreach (var (key, use) in Places) {
            if (use.TypedAt is not { } typed) continue;
            int end = key.IndexOfAny([':', '/', '?']);
            string host = end < 0 ? key : key[..end];
            if (!hosts.TryGetValue(host, out var known) || known < typed) hosts[host] = typed;
        }
        return hosts.ToImmutable();
    }

    /// A pick's uses at `now`, decayed for each day since it was last used.
    private static double Current(PaletteChoice choice, DateTimeOffset now) =>
        choice.Uses * Math.Pow(DailyChoiceDecay, Math.Max(0, (now - choice.LastUsedAt).TotalDays));

    /// The frecency on `day` of a place whose score reaches one on `decayDay`.
    private static double Score(double decayDay, double day) => Math.Pow(2, (decayDay - day) / HalfLifeDays);

    /// `at` as days from the Unix epoch.
    public static double Day(DateTimeOffset at) => (at - DateTimeOffset.UnixEpoch).TotalDays;

    /// What a person typed, as picks remember it: trimmed, lower case, single-spaced.
    public static string Folded(string typed) =>
        string.Join(' ', typed.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)).ToLowerInvariant();

    #endregion
}
