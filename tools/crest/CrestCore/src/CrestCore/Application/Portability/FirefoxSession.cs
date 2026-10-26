using System.Text.Json;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// Firefox's session, `recovery.jsonlz4` or `sessionstore.jsonlz4`: its
/// windows, each with its open and pinned tabs and its tab groups, each a
/// folder of open tabs in the group's color, the window it had selected
/// first.
internal static class FirefoxSession {
    #region Static Variables

    /// The color Firefox spells `gray`, which Chrome and Crest spell `grey`.
    private const string FirefoxGray = "gray";

    #endregion

    #region Actions - Reading

    /// The windows the session holds, however many. Throws `Rejected` with
    /// `SessionUnrecognized` for a file that is not Firefox's session, and
    /// `SessionOverLimits` for one larger than an import decodes.
    public static IReadOnlyList<SessionDraft> Read(byte[] contents, DateTimeOffset importedAt) {
        using var document = ImportJson.Parse(MozillaLz4.Decoded(contents)) ?? throw new Rejected(new SessionUnrecognized());
        var root = ImportJson.Object(document.RootElement);
        var windows = ImportJson.Array(ImportJson.Member(root, "windows"));
        if (root is null || windows is null) throw new Rejected(new SessionUnrecognized());
        List<SessionDraft> drafts = [];
        for (int index = 0; index < windows.Count; index++) {
            var window = windows[index];
            if (ImportJson.Object(window) is null || ImportJson.Array(ImportJson.Member(window, "tabs")) is not { } tabs) continue;
            var groups = Groups(window);
            var read = tabs.Select(tab => Tab(tab, groups, importedAt)).OfType<SessionTab>().ToArray();
            SessionFolder[] folders = [.. read.Select(tab => tab.FolderSourceId).OfType<string>().Distinct(StringComparer.Ordinal)
                .Select(id => groups[id])];
            drafts.Add(new SessionDraft(index + 1, ImportJson.Text(ImportJson.Member(window, "title")), folders, read));
        }
        long selected = Math.Max(1, ImportJson.Integer(ImportJson.Member(root, "selectedWindow")) ?? 1);
        if (drafts.FindIndex(draft => draft.Ordinal == selected) is > 0 and var first) {
            var draft = drafts[first];
            drafts.RemoveAt(first);
            drafts.Insert(0, draft);
        }
        return drafts;
    }

    /// The window's tab groups by identity, each a folder of open tabs.
    private static Dictionary<string, SessionFolder> Groups(JsonElement window) {
        Dictionary<string, SessionFolder> groups = new(StringComparer.Ordinal);
        foreach (var group in ImportJson.Array(ImportJson.Member(window, "groups")) ?? []) {
            if (ImportJson.Text(ImportJson.Member(group, "id")) is not { } id) continue;
            string? color = ImportJson.Text(ImportJson.Member(group, "color"));
            groups[id] = new SessionFolder(id, ImportJson.Text(ImportJson.Member(group, "name")) ?? "", ParentSourceId: null,
                TabPlacement.Current, TabGroupColor.Named(color == FirefoxGray ? TabGroupColor.Grey.Name : color) ?? TabGroupColor.Grey);
        }
        return groups;
    }

    /// The page a tab shows: its selected history entry, in the group of
    /// `groups` it names unless it is pinned.
    private static SessionTab? Tab(JsonElement tab, IReadOnlyDictionary<string, SessionFolder> groups, DateTimeOffset importedAt) {
        if (ImportJson.Object(tab) is null || ImportJson.Array(ImportJson.Member(tab, "entries")) is not { Count: > 0 } entries) return null;
        long selected = Math.Min(Math.Max(0, (ImportJson.Integer(ImportJson.Member(tab, "index")) ?? 1) - 1), entries.Count - 1);
        var entry = entries[(int)selected];
        if (ImportJson.Object(entry) is null || ImportJson.Text(ImportJson.Member(entry, "url")) is not { } url
            || ImportAddress.Read(url) is not { } address) return null;
        var time = ImportJson.Number(ImportJson.Member(tab, "lastAccessed")) is { } raw ? ImportDate.FromUnixMilliseconds(raw) : null;
        bool pinned = ImportJson.Flag(ImportJson.Member(tab, "pinned")) ?? false;
        string? group = !pinned && ImportJson.Text(ImportJson.Member(tab, "groupId")) is { } id && groups.ContainsKey(id) ? id : null;
        return new SessionTab(ImportJson.Text(ImportJson.Member(entry, "title")) ?? "", address,
            pinned ? TabPlacement.Pinned : TabPlacement.Current, group, time ?? importedAt);
    }

    #endregion
}
