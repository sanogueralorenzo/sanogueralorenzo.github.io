using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Projects the native checkpoint format onto the existing CloudKit payload
/// format. Wire encoding lives here; portable-content and ordering rules are domain rules.
public static class NativeSyncProjection {
    #region Actions - Projection

    internal static Guid Id(JsonNode? value) => SyncJson.Identity(value);

    internal static string? Text(JsonNode? value) => value?.GetValue<string>();

    internal static JsonArray Items(JsonNode value, string field) => value[field]?.AsArray() ?? [];

    internal static JsonObject Fields(JsonNode source, params string[] names)
        => new(names.Where(n => source[n] is not null).Select(n => new KeyValuePair<string, JsonNode?>(n, source[n]!.DeepClone())));

    internal static TabPlacement Placement(JsonNode value, string field = "placement")
        => TabPlacement.Named(Text(value[field])) ?? throw new BrowserRuleException(BrowserRule.InvalidSyncPlacement);

    internal static string? SavedUrl(JsonNode tab) => Text(tab["savedURL"])
        ?? (Placement(tab).IsDurable ? Text(tab["url"]) : null);

    internal static bool PortableTab(JsonNode tab) => SyncedAddress.IncludesTab(Text(tab["url"]), tab["nativeContent"] is not null, SavedUrl(tab));

    /// A stored archive record's reason as sync spells it. A reason this build
    /// does not know keeps its stored spelling.
    internal static string ArchiveReasonName(JsonNode archive) {
        string stored = Text(archive["reason"])!;
        return ArchiveReason.Stored(stored, Text(archive["deletionOrigin"]))?.Name ?? stored;
    }

    /// The reason a synced archive record carries, given the one the shared
    /// record carried before.
    private static string SyncedArchiveReason(JsonNode archive, string? shared) {
        string name = ArchiveReasonName(archive);
        return ArchiveReason.Named(name)?.SyncProjection(shared) ?? name;
    }

    internal static SyncPreferences Preferences(JsonNode source) => new(
        source["savedStructure"]!.GetValue<bool>(), source["currentTabs"]!.GetValue<bool>(), source["historyAndArchive"]!.GetValue<bool>());

    public static JsonArray Project(JsonObject session, JsonNode preferences, IEnumerable<JsonObject> existingRecords) {
        var policy = Preferences(preferences);
        var existing = new Dictionary<string, string?>(StringComparer.Ordinal);
        var archiveReasons = new Dictionary<Guid, string?>();
        foreach (var record in existingRecords) {
            if (record["payload"]?["value"] is not JsonObject value) continue;
            var type = SyncPayloadType.Of(record["payload"]!);
            var id = Id(record["id"]!["value"]);
            existing[type.Kind.RecordName(id)] = Text(type.Subject(value)["orderToken"]);
            if (type == SyncPayloadType.Archive) archiveReasons[id] = Text(value["reason"]);
        }
        var result = new JsonArray();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        void Add(SyncPayloadType type, JsonObject value) {
            string name = type.Kind.RecordName(Id(type.Subject(value)["id"]));
            if (!seen.Add(name)) throw new SyncRecordsFlawedException(SyncRecordFlaw.DuplicateRecord, subject: null);
            if (seen.Count > NativeSyncJournal.MaximumRecords) throw new SyncRecordsFlawedException(SyncRecordFlaw.TooManyRecords, subject: null);
            result.Add((JsonNode)new JsonObject { ["type"] = type.Kind.Name, ["value"] = value });
        }
        IReadOnlyList<string> Tokens(SyncPayloadType type, IReadOnlyList<JsonNode> items)
            => SyncOrderTokens.Allocate(items.Select(item => existing.GetValueOrDefault(type.Kind.RecordName(Id(type.Subject(item.AsObject())["id"]))))
                .ToArray());

        var spaces = Items(session, "spaces").Select(n => n!).ToArray();
        var spaceTokens = Tokens(SyncPayloadType.Space, spaces);
        for (int i = 0; i < spaces.Length; i++) {
            var space = spaces[i];
            var portable = Items(space, StoredSessionCodec.Key.Tabs).Where(t => PortableTab(t!)).Select(t => t!).ToArray();
            var splitIds = portable.Where(t => t["splitGroupID"] is not null).Select(t => Id(t["splitGroupID"])).ToHashSet();
            var spaceValue = Fields(space, "id", "name", "symbol", "accent", "branding", "browsingPreferences",
                "accessPolicy", "accessPolicyModifiedAt", "isSavedTabsExpanded", "savedTabsExpansionModifiedAt");
            spaceValue["profileID"] = space["profile"]!["id"]!.DeepClone();
            if (space[StoredSessionCodec.Key.CredentialsEnabledModifiedAt] is { } credentialsModifiedAt) {
                spaceValue["credentialsEnabled"] = StoredSessionCodec.DecodeCredentialPreferences(
                    space[StoredSessionCodec.Key.CredentialPreferences] ?? new JsonObject()).IsEnabled;
                spaceValue["credentialsEnabledModifiedAt"] = credentialsModifiedAt.DeepClone();
            }
            SyncedText.SpaceName.Fit(spaceValue);
            SyncedText.SpaceSymbol.Fit(spaceValue);
            spaceValue["splitGroups"] = new JsonArray(Items(space, "splitGroups")
                .Where(g => splitIds.Contains(Id(g!["id"]))).DistinctBy(g => Id(g!["id"])).Select(SplitGroup).ToArray());
            spaceValue["orderToken"] = spaceTokens[i];
            Add(SyncPayloadType.Space, spaceValue);

            if (policy.CurrentTabs || policy.SavedStructure) {
                var folders = Items(space, StoredSessionCodec.Key.Folders).Where(f => policy.Includes(Placement(f!, "location"))).Select(f => f!).ToArray();
                var tree = new FolderTree(folders.Select(f => new FolderState(Id(f["id"]), Placement(f, "location"),
                    Text(f["title"])!, ParentId: f["parentID"] is { } parent ? Id(parent) : null)).ToArray());
                IReadOnlyList<FolderState> display;
                try { display = tree.DisplayOrder(); } catch (BrowserRuleException) { throw new SyncRecordsFlawedException(SyncRecordFlaw.InvalidFolderHierarchy, Id(space["id"])); }
                var byId = folders.ToDictionary(f => Id(f["id"]));
                var folderTokens = new Dictionary<Guid, string>();
                foreach (var parent in new Guid?[] { null }.Concat(display.Select(f => (Guid?)f.Id))) {
                    var children = tree.Children(parent).ToArray();
                    var tokens = Tokens(SyncPayloadType.Folder, children.Select(f => byId[f.Id]).ToArray());
                    for (int j = 0; j < children.Length; j++) folderTokens[children[j].Id] = tokens[j];
                }
                foreach (var folder in display) {
                    var value = Fields(byId[folder.Id], "id", "title", "location", "symbol", "color", "parentID",
                        "isCollapsed", "collapseModifiedAt", "orderAnchorTabID");
                    value["spaceID"] = space["id"]!.DeepClone();
                    value["orderToken"] = folderTokens[folder.Id];
                    SyncedText.FolderTitle.Fit(value);
                    SyncedText.FolderSymbol.Fit(value);
                    Add(SyncPayloadType.Folder, value);
                }
            }

            var tabs = portable.Where(t => policy.Includes(Placement(t))).ToArray();
            var tabTokens = Tokens(SyncPayloadType.Tab, tabs);
            for (int j = 0; j < tabs.Length; j++) Add(SyncPayloadType.Tab, Tab(tabs[j], space["id"]!, tabTokens[j], archived: false));
            if (!policy.HistoryAndArchive) continue;
            foreach (var history in Items(space, StoredSessionCodec.Key.History).Where(h => SyncedAddress.Includes(Text(h!["url"])))) {
                var value = Fields(history!, "id", "url", "title", "firstVisitedAt", "lastVisitedAt", "visitCount");
                value["spaceID"] = space["id"]!.DeepClone();
                Spell(value, "url");
                Visit(value);
                Add(SyncPayloadType.History, value);
            }
            // Archive presentation sorts by date after a merge. That is not a
            // user reorder: keep accepted positions and append new identities.
            var archive = Items(space, StoredSessionCodec.Key.ArchivedTabs).Where(a => PortableTab(a!["tab"]!)).Select(a => a!)
                .OrderBy(a => existing.GetValueOrDefault(SyncPayloadType.Archive.Kind.RecordName(Id(a["tab"]!["id"]))) ?? "~", StringComparer.Ordinal)
                .ThenBy(a => Id(a["tab"]!["id"]).ToString("D"), StringComparer.Ordinal).ToArray();
            var archiveTokens = Tokens(SyncPayloadType.Archive, archive);
            for (int j = 0; j < archive.Length; j++) Add(SyncPayloadType.Archive, new JsonObject {
                ["tab"] = Tab(archive[j]["tab"]!, space["id"]!, archiveTokens[j], archived: true),
                ["archivedAt"] = archive[j]["archivedAt"]!.DeepClone(),
                ["reason"] = SyncedArchiveReason(archive[j], archiveReasons.GetValueOrDefault(Id(archive[j]["tab"]!["id"])))
            });
        }
        return result;
    }

    private static JsonObject Tab(JsonNode source, JsonNode spaceId, string token, bool archived) {
        var value = Fields(source, "id", "title", "url", "symbol", "lastActivatedAt", "positionModifiedAt", "customTitle", "titleModifiedAt", "keepsPageLoaded");
        value["spaceID"] = spaceId.DeepClone(); value["orderToken"] = token;
        Spell(value, "url");
        value["placement"] = archived ? JsonValue.Create(TabPlacement.Current.Name) : source["placement"]!.DeepClone();
        if (!archived) {
            if (SavedUrl(source) is { } saved) value["savedURL"] = new SyncedAddress(saved).Spelled ?? saved;
            // Only a placement that holds folders names one: a pinned tab never does.
            if (source["folderID"] is { } folder && Placement(source).HoldsFolders) value["folderID"] = folder.DeepClone();
            if (source["splitGroupID"] is { } split) value["splitGroupID"] = split.DeepClone();
        }
        SyncedText.TabTitle.Fit(value);
        SyncedText.TabCustomTitle.Fit(value);
        SyncedText.TabSymbol.Fit(value);
        return value;
    }

    /// Writes the address `field` holds as every client parses it.
    private static void Spell(JsonObject value, string field) {
        if (value[field] is JsonValue address && address.TryGetValue<string>(out var text) && new SyncedAddress(text).Spelled is { } spelled
            && spelled != text) value[field] = spelled;
    }

    /// A split's metadata as every client reads it.
    private static JsonNode SplitGroup(JsonNode? source) {
        var group = source!.DeepClone().AsObject();
        SyncedText.SplitTitle.Fit(group);
        SyncedText.SplitIcon.Fit(group);
        return group;
    }

    /// A visit as every client reads it: titled, counted at least once, and
    /// first visited no later than last. A session that holds it otherwise
    /// keeps it; only the record is fitted.
    private static void Visit(JsonObject value) {
        SyncedText.HistoryTitle.Fit(value);
        if (SyncJson.TryInt(value["visitCount"], out var visits) && visits < 1) value["visitCount"] = 1;
        if (SyncJson.TryDouble(value["firstVisitedAt"], out var firstVisited) && SyncJson.TryDouble(value["lastVisitedAt"], out var lastVisited)
            && firstVisited > lastVisited)
            value["firstVisitedAt"] = value["lastVisitedAt"]!.DeepClone();
    }

    #endregion
}
