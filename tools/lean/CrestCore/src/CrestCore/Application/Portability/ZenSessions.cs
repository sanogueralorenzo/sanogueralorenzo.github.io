using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Zen's `zen-sessions.jsonlz4`: its Spaces, folders and tabs. Each Space
/// brings the Essentials as pinned tabs, its pinned tabs as saved tabs in
/// their folders, and its other tabs as open tabs, with its name.
/// Zen keeps a split view as a group of its own, which is no folder: a pinned
/// tab in one is saved in the folder holding the split, or outside any folder
/// for a split among the Space's pinned tabs, and the split comes along as a
/// split of its tabs.
internal static class ZenSessions {
    #region Static Variables

    private const string UntitledFolder = "Untitled Folder";

    #endregion

    #region Types

    /// One of Zen's `folders`: a folder of a Space's pinned tabs, or a split
    /// view inside one, which names no Space.
    private sealed record Group(string Id, string? Name, string? ParentId, string? Workspace, bool IsSplit);

    #endregion

    #region Actions - Reading

    /// The Spaces the session holds, in order, however many: those past the
    /// most a workspace holds with their names alone, which an import leaves
    /// out. Throws `Rejected` with `SessionUnrecognized` for a file that is
    /// not Zen's session, and `SessionOverLimits` for one larger than an
    /// import decodes.
    public static IReadOnlyList<SessionDraft> Read(byte[] contents, DateTimeOffset importedAt) {
        using var document = ImportJson.Parse(MozillaLz4.Decoded(contents)) ?? throw new Rejected(new SessionUnrecognized());
        var root = ImportJson.Object(document.RootElement) ?? throw new Rejected(new SessionUnrecognized());
        var spaces = ImportJson.Array(ImportJson.Member(root, "spaces"));
        var tabs = ImportJson.Array(ImportJson.Member(root, "tabs"));
        if (spaces is null || tabs is null || spaces.Count == 0) throw new Rejected(new SessionUnrecognized());
        var all = (ImportJson.Array(ImportJson.Member(root, "folders")) ?? []).Select(Folder).OfType<Group>().ToArray();
        Dictionary<string, Group> groups = new(StringComparer.Ordinal);
        foreach (var group in all) groups.TryAdd(group.Id, group);
        var splits = Splits(root, all);
        // An Essential no Space claims is pinned in every Space.
        var owned = tabs.Where(tab => ImportJson.Object(tab) is not null).Select(tab => (Tab: tab,
            Owner: ImportJson.Text(ImportJson.Member(tab, "zenWorkspace")),
            Essential: ImportJson.Flag(ImportJson.Member(tab, "zenEssential")) ?? false)).ToArray();

        List<SessionDraft> drafts = [];
        for (int index = 0; index < spaces.Count; index++) {
            var space = spaces[index];
            if (ImportJson.Object(space) is null || ImportJson.Text(ImportJson.Member(space, "uuid")) is not { } workspace) continue;
            string name = ImportJson.Text(ImportJson.Member(space, "name")) ?? $"Zen Space {index + 1}";
            if (drafts.Count >= BrowserDataFile.MaximumSpaces) {
                drafts.Add(new SessionDraft(index + 1, name, [], []));
                continue;
            }
            var spaceGroups = all.Where(group => !group.IsSplit && group.Workspace == workspace).ToArray();
            HashSet<string> kept = [.. spaceGroups.Select(group => group.Id)];
            var spaceFolders = spaceGroups.Select(group => new SessionFolder(group.Id, group.Name ?? UntitledFolder,
                Holder(group.ParentId, groups, kept))).ToArray();
            List<SessionTab> spaceTabs = [];
            foreach (var (tab, owner, essential) in owned)
                if ((owner == workspace || (owner is null && essential))
                    && Tab(tab, Holder(ImportJson.Text(ImportJson.Member(tab, "groupId")), groups, kept), splits, importedAt) is { } decoded)
                    spaceTabs.Add(decoded);
            drafts.Add(new SessionDraft(index + 1, name, spaceFolders, spaceTabs));
        }
        return drafts;
    }

    /// The group one of Zen's `folders` describes, spelled in either case,
    /// or null for one without an identity.
    private static Group? Folder(JsonElement folder) =>
        ImportJson.Object(folder) is null || ImportJson.Text(ImportJson.Member(folder, "id")) is not { } id ? null
            : new(id, ImportJson.Text(ImportJson.Member(folder, "name")),
                ImportJson.Text(ImportJson.Member(folder, "parentId")) ?? ImportJson.Text(ImportJson.Member(folder, "parentID")),
                ImportJson.Text(ImportJson.Member(folder, "workspaceId")) ?? ImportJson.Text(ImportJson.Member(folder, "workspaceID")),
                ImportJson.Flag(ImportJson.Member(folder, "splitViewGroup")) ?? false);

    /// The folder of a Space, among `kept`, that holds what names `group`:
    /// that folder, or the one holding the split view it names, or none for a
    /// split among the Space's pinned tabs or a group the Space does not keep.
    private static string? Holder(string? group, IReadOnlyDictionary<string, Group> groups, IReadOnlySet<string> kept) {
        for (int depth = 0; group is not null && depth <= groups.Count; depth++) {
            if (kept.Contains(group)) return group;
            group = groups.TryGetValue(group, out var split) && split.IsSplit ? split.ParentId : null;
        }
        return null;
    }

    /// The split views the session keeps, by identity: those `splitViewData`
    /// lists, the groups marked as one, and the folders that are one.
    private static HashSet<string> Splits(JsonElement root, IReadOnlyList<Group> folders) {
        HashSet<string> splits = new(StringComparer.Ordinal);
        foreach (var split in ImportJson.Array(ImportJson.Member(root, "splitViewData")) ?? [])
            if (ImportJson.Text(ImportJson.Member(split, "groupId")) is { } id) splits.Add(id);
        foreach (var group in ImportJson.Array(ImportJson.Member(root, "groups")) ?? [])
            if (ImportJson.Flag(ImportJson.Member(group, "splitView")) == true && ImportJson.Text(ImportJson.Member(group, "id")) is { } id)
                splits.Add(id);
        foreach (var folder in folders.Where(folder => folder.IsSplit)) splits.Add(folder.Id);
        return splits;
    }

    /// The page a tab shows: its selected history entry. Essentials are
    /// pinned tabs, and pinned tabs are saved tabs in `folder`. A tab in one
    /// of `splits` shows in that split.
    private static SessionTab? Tab(JsonElement tab, string? folder, IReadOnlySet<string> splits, DateTimeOffset importedAt) {
        if (ImportJson.Array(ImportJson.Member(tab, "entries")) is not { Count: > 0 } entries) return null;
        long selected = Math.Min(Math.Max(0, (ImportJson.Integer(ImportJson.Member(tab, "index")) ?? 1) - 1), entries.Count - 1);
        var entry = entries[(int)selected];
        if (ImportJson.Object(entry) is null || ImportJson.Text(ImportJson.Member(entry, "url")) is not { } url
            || ImportAddress.Read(url) is not { } address) return null;
        bool essential = ImportJson.Flag(ImportJson.Member(tab, "zenEssential")) ?? false;
        bool pinned = ImportJson.Flag(ImportJson.Member(tab, "pinned")) ?? false;
        var placement = essential ? TabPlacement.Pinned : pinned ? TabPlacement.Saved : TabPlacement.Current;
        var time = ImportJson.Number(ImportJson.Member(tab, "lastAccessed")) is { } raw ? ImportDate.FromUnixSecondsOrMilliseconds(raw) : null;
        string? split = ImportJson.Text(ImportJson.Member(tab, "groupId")) is { } group && splits.Contains(group) ? group : null;
        return new SessionTab(ImportJson.Text(ImportJson.Member(entry, "title")) ?? "", address, placement,
            placement == TabPlacement.Saved ? folder : null, time ?? importedAt, split);
    }

    #endregion

    #region Actions - Looks

    #endregion
}
