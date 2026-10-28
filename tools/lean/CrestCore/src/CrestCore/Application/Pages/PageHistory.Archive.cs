using System.Text.Json;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// A page's history as its tab's archive keeps it across a relaunch: a JSON
/// object of its runs, the run the page shows, the identities its engine held
/// then, and what each engine handed back for the runs it held, within
/// `ArchivedStateBudget` as stored. Past the budget the oldest runs' engine
/// history is left out first, and their entries load afresh. The run the page
/// shows needs none: the tab's archive keeps its engine's own. An archive this
/// build cannot read brings back nothing.
internal sealed partial class PageHistory {
    #region Static Variables

    /// The format this build writes and reads.
    private const int ArchiveVersion = 1;

    /// The most bytes of engine history an archive keeps, as it stores them.
    public const int ArchivedStateBudget = 2 * 1024 * 1024;

    private const string VersionName = "version";
    private const string LiveName = "live";
    private const string NativeName = "native";
    private const string KeptName = "kept";
    private const string RunsName = "runs";
    private const string UrlName = "url";
    private const string StateName = "state";
    private const string EngineName = "engine";
    private const string CurrentName = "current";
    private const string StartName = "start";
    private const string BoundaryName = "boundary";
    private const string EntriesName = "entries";
    private const string IdName = "id";
    private const string TitleName = "title";

    #endregion

    #region Actions - Archive

    /// The history as its tab's archive keeps it, or null for a page that
    /// shows no entry yet.
    public byte[]? Archive() {
        if (Shown is null) return null;
        var kept = new List<Kept>();
        long bytes = 0;
        for (int index = runs.Count - 1; index >= 0; index--) {
            if (index == live || runs[index].Saved is not { } saved || kept.Contains(saved, ReferenceEqualityComparer.Instance))
                continue;
            // Engine history is stored as base64.
            long stored = (saved.State.State.Length + 2L) / 3 * 4;
            if (bytes + stored > ArchivedStateBudget) continue;
            bytes += stored;
            kept.Add(saved);
        }
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream)) {
            writer.WriteStartObject();
            writer.WriteNumber(VersionName, ArchiveVersion);
            writer.WriteNumber(LiveName, live);
            // A page still restoring holds what its engine is bringing back.
            WriteIdentities(writer, NativeName, arriving?.Native ?? native);
            writer.WriteStartArray(KeptName);
            foreach (var saved in kept) {
                writer.WriteStartObject();
                writer.WriteString(UrlName, saved.State.Url);
                writer.WriteBase64String(StateName, saved.State.State);
                WriteIdentities(writer, NativeName, saved.Native);
                writer.WriteEndObject();
            }
            writer.WriteEndArray();
            writer.WriteStartArray(RunsName);
            foreach (var run in runs) {
                writer.WriteStartObject();
                writer.WriteString(EngineName, run.Engine.Name);
                writer.WriteNumber(CurrentName, run.Current);
                if (run.Start is { } start) writer.WriteString(StartName, start);
                if (run.Boundary is { } boundary) writer.WriteString(BoundaryName, boundary);
                if (run.Saved is { } saved && kept.FindIndex(each => ReferenceEquals(each, saved)) is var at and >= 0)
                    writer.WriteNumber(KeptName, at);
                writer.WriteStartArray(EntriesName);
                foreach (var entry in run.Entries) {
                    writer.WriteStartObject();
                    writer.WriteString(IdName, entry.Id);
                    writer.WriteString(UrlName, entry.Url);
                    writer.WriteString(TitleName, entry.Title);
                    writer.WriteEndObject();
                }
                writer.WriteEndArray();
                writer.WriteEndObject();
            }
            writer.WriteEndArray();
            writer.WriteEndObject();
        }
        return stream.ToArray();
    }

    /// The history `archive` keeps, or null when this build cannot read it,
    /// or it holds a history no engine could have reported: more than
    /// `Capacity` entries, an entry twice, no entry to show, a missing
    /// address or title, a run that ends before it starts, or more engine
    /// history than `ArchivedStateBudget`.
    public static PageHistory? Unarchive(byte[]? archive) {
        if (archive is null || archive.Length == 0) return null;
        try {
            using var document = JsonDocument.Parse(archive, new() { MaxDepth = 8 });
            var root = document.RootElement;
            if (root.GetProperty(VersionName).GetInt32() != ArchiveVersion) return null;
            var kept = root.GetProperty(KeptName).EnumerateArray()
                .Select(saved => new Kept(new PageRestoreState(Text(saved, UrlName), saved.GetProperty(StateName).GetBytesFromBase64()),
                    Identities(saved.GetProperty(NativeName))))
                .ToList();
            if (kept.Sum(saved => (long)saved.State.State.Length) > ArchivedStateBudget
                || kept.Any(saved => saved.Native.Distinct().Count() != saved.Native.Count))
                return null;
            var history = new PageHistory { live = root.GetProperty(LiveName).GetInt32(), native = Identities(root.GetProperty(NativeName)) };
            foreach (var stored in root.GetProperty(RunsName).EnumerateArray()) {
                if (EngineKind.Named(Text(stored, EngineName)) is not { } engine) return null;
                var run = new Run(engine) {
                    Current = stored.GetProperty(CurrentName).GetInt32(),
                    Start = stored.TryGetProperty(StartName, out var start) ? start.GetGuid() : null,
                    Boundary = stored.TryGetProperty(BoundaryName, out var boundary) ? boundary.GetGuid() : null,
                    Saved = stored.TryGetProperty(KeptName, out var at) ? kept[at.GetInt32()] : null,
                    Entries = [.. stored.GetProperty(EntriesName).EnumerateArray().Select(entry => new PageHistoryEntry(
                        entry.GetProperty(IdName).GetGuid(), Text(entry, UrlName), Text(entry, TitleName)))],
                };
                if (run.Entries.Count == 0 || run.Current < 0 || run.Current >= run.Entries.Count) return null;
                int first = run.Start is { } begins ? run.Entries.FindIndex(entry => entry.Id == begins) : 0;
                int last = run.Boundary is { } ends ? run.Entries.FindIndex(entry => entry.Id == ends) : run.Entries.Count - 1;
                if (first >= 0 && last >= 0 && last < first) return null;
                history.runs.Add(run);
            }
            var entries = history.Entries;
            return history.live >= 0 && history.live < history.runs.Count && entries.Count <= Capacity
                && entries.Select(entry => entry.Id).Distinct().Count() == entries.Count
                    ? history
                    : null;
        } catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException
            or FormatException or ArgumentOutOfRangeException) {
            return null;
        }
    }

    private static void WriteIdentities(Utf8JsonWriter writer, string name, IReadOnlyList<Guid> identities) {
        writer.WriteStartArray(name);
        foreach (var identity in identities) writer.WriteStringValue(identity);
        writer.WriteEndArray();
    }

    /// The string `name` names in `element`, which must not be null.
    private static string Text(JsonElement element, string name) =>
        element.GetProperty(name).GetString() ?? throw new FormatException($"{name} is null");

    private static List<Guid> Identities(JsonElement array) => [.. array.EnumerateArray().Select(identity => identity.GetGuid())];

    #endregion
}
