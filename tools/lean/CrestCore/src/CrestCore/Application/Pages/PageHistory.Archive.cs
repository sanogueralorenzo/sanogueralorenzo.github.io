using System.Text.Json;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// The bounded browser history saved alongside WebKit's opaque state.
/// Native state has one owner in the tab archive; this document holds entries only.
internal sealed partial class PageHistory {
    #region Static Variables

    /// The format this build writes and reads.
    private const int ArchiveVersion = 2;

    private const string VersionName = "version";
    private const string LiveName = "live";
    private const string NativeName = "native";
    private const string RunsName = "runs";
    private const string UrlName = "url";
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
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream)) {
            writer.WriteStartObject();
            writer.WriteNumber(VersionName, ArchiveVersion);
            writer.WriteNumber(LiveName, live);
            // A page still restoring holds what its engine is bringing back.
            WriteIdentities(writer, NativeName, arriving?.Native ?? native);
            writer.WriteStartArray(RunsName);
            foreach (var run in runs) {
                writer.WriteStartObject();
                writer.WriteNumber(CurrentName, run.Current);
                if (run.Start is { } start) writer.WriteString(StartName, start);
                if (run.Boundary is { } boundary) writer.WriteString(BoundaryName, boundary);
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

    /// Restores only valid bounded history: unique entries with a current entry,
    /// non-null addresses and titles, and valid slice boundaries.
    public static PageHistory? Unarchive(byte[]? archive) {
        if (archive is null || archive.Length == 0) return null;
        try {
            using var document = JsonDocument.Parse(archive, new() { MaxDepth = 8 });
            var root = document.RootElement;
            if (root.GetProperty(VersionName).GetInt32() != ArchiveVersion) return null;
            var history = new PageHistory { live = root.GetProperty(LiveName).GetInt32(), native = Identities(root.GetProperty(NativeName)) };
            foreach (var stored in root.GetProperty(RunsName).EnumerateArray()) {
                var run = new Run() {
                    Current = stored.GetProperty(CurrentName).GetInt32(),
                    Start = stored.TryGetProperty(StartName, out var start) ? start.GetGuid() : null,
                    Boundary = stored.TryGetProperty(BoundaryName, out var boundary) ? boundary.GetGuid() : null,
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
