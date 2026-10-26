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

    /// The members of `members` a record copies from the stored value it
    /// projects; the projection places it in its Space and among its siblings.
    private static string[] Copied(IReadOnlyList<string> members) =>
        members.Where(member => member is not StoredSessionCodec.Key.SpaceId and not SyncPayload.Key.OrderToken).ToArray();

    internal static TabPlacement Placement(JsonNode value, string field = StoredSessionCodec.Key.Placement)
        => TabPlacement.Named(Text(value[field])) ?? throw new BrowserRuleException(BrowserRule.InvalidSyncPlacement);

    internal static string? SavedUrl(JsonNode tab) => Text(tab[StoredSessionCodec.Key.SavedUrl])
        ?? (Placement(tab).IsDurable ? Text(tab[StoredSessionCodec.Key.Url]) : null);

    internal static bool PortableTab(JsonNode tab) => SyncedAddress.IncludesTab(Text(tab[StoredSessionCodec.Key.Url]),
        tab[StoredSessionCodec.Key.NativeContent] is not null, SavedUrl(tab));

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
        foreach (var json in existingRecords) {
            var record = new SyncJournalRecord(json);
            if (record.Payload?[SyncPayload.Key.Value] is not JsonObject value) continue;
            var type = SyncPayloadType.Of(record.Payload);
            existing[type.Kind.RecordName(record.Id)] = Text(type.Subject(value)[SyncPayload.Key.OrderToken]);
            if (type == SyncPayloadType.Archive) archiveReasons[record.Id] = Text(value[StoredSessionCodec.Key.Reason]);
        }
        var result = new JsonArray();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        void Add(SyncPayloadType type, JsonObject value) {
            string name = type.Kind.RecordName(Id(type.Subject(value)[StoredSessionCodec.Key.Id]));
            if (!seen.Add(name)) throw new SyncRecordsFlawedException(SyncRecordFlaw.DuplicateRecord, subject: null);
            if (seen.Count > NativeSyncJournal.MaximumRecords) throw new SyncRecordsFlawedException(SyncRecordFlaw.TooManyRecords, subject: null);
            result.Add((JsonNode)SyncPayload.Envelope(type.Kind, value));
        }
        IReadOnlyList<string> Tokens(SyncPayloadType type, IReadOnlyList<JsonNode> items)
            => SyncOrderTokens.Allocate(items.Select(item =>
                existing.GetValueOrDefault(type.Kind.RecordName(Id(type.Subject(item.AsObject())[StoredSessionCodec.Key.Id]))))
                .ToArray());

        var spaces = Items(session, StoredSessionCodec.Key.Spaces).Select(n => n!).ToArray();
        var spaceTokens = Tokens(SyncPayloadType.Space, spaces);
        for (int i = 0; i < spaces.Length; i++) {
            var space = spaces[i];
            var portable = Items(space, StoredSessionCodec.Key.Tabs).Where(t => PortableTab(t!)).Select(t => t!).ToArray();
            var splitIds = portable.Where(t => t[StoredSessionCodec.Key.SplitGroupId] is not null)
                .Select(t => Id(t[StoredSessionCodec.Key.SplitGroupId])).ToHashSet();
            // A Space's profile, credentials choice, splits and position are
            // its record's own; the rest is copied as the session holds it.
            var spaceValue = Fields(space, StoredSessionCodec.Key.Id, StoredSessionCodec.Key.Name, StoredSessionCodec.Key.Symbol,
                StoredSessionCodec.Key.Accent, StoredSessionCodec.Key.Branding, StoredSessionCodec.Key.BrowsingPreferences,
                StoredSessionCodec.Key.AccessPolicy, StoredSessionCodec.Key.AccessPolicyModifiedAt, StoredSessionCodec.Key.IsSavedTabsExpanded,
                StoredSessionCodec.Key.SavedTabsExpansionModifiedAt);
            spaceValue[StoredSessionCodec.Key.ProfileId] = space[StoredSessionCodec.Key.Profile]![StoredSessionCodec.Key.Id]!.DeepClone();
            if (space[StoredSessionCodec.Key.CredentialsEnabledModifiedAt] is { } credentialsModifiedAt) {
                spaceValue[SyncPayload.Key.CredentialsEnabled] = StoredSessionCodec.DecodeCredentialPreferences(
                    space[StoredSessionCodec.Key.CredentialPreferences] ?? new JsonObject()).IsEnabled;
                spaceValue[StoredSessionCodec.Key.CredentialsEnabledModifiedAt] = credentialsModifiedAt.DeepClone();
            }
            SyncedText.SpaceName.Fit(spaceValue);
            SyncedText.SpaceSymbol.Fit(spaceValue);
            spaceValue[StoredSessionCodec.Key.SplitGroups] = new JsonArray(Items(space, StoredSessionCodec.Key.SplitGroups)
                .Where(g => splitIds.Contains(Id(g![StoredSessionCodec.Key.Id]))).DistinctBy(g => Id(g![StoredSessionCodec.Key.Id]))
                .Select(SplitGroup).ToArray());
            spaceValue[SyncPayload.Key.OrderToken] = spaceTokens[i];
            Add(SyncPayloadType.Space, spaceValue);

            if (policy.CurrentTabs || policy.SavedStructure) {
                var folders = Items(space, StoredSessionCodec.Key.Folders)
                    .Where(f => policy.Includes(Placement(f!, StoredSessionCodec.Key.Location))).Select(f => f!).ToArray();
                var tree = new FolderTree(folders.Select(f => new FolderState(Id(f[StoredSessionCodec.Key.Id]),
                    Placement(f, StoredSessionCodec.Key.Location), Text(f[StoredSessionCodec.Key.Title])!,
                    ParentId: f[StoredSessionCodec.Key.ParentId] is { } parent ? Id(parent) : null)).ToArray());
                IReadOnlyList<FolderState> display;
                try { display = tree.DisplayOrder(); } catch (BrowserRuleException) { throw new SyncRecordsFlawedException(SyncRecordFlaw.InvalidFolderHierarchy, Id(space["id"])); }
                var byId = folders.ToDictionary(f => Id(f[StoredSessionCodec.Key.Id]));
                var folderTokens = new Dictionary<Guid, string>();
                foreach (var parent in new Guid?[] { null }.Concat(display.Select(f => (Guid?)f.Id))) {
                    var children = tree.Children(parent).ToArray();
                    var tokens = Tokens(SyncPayloadType.Folder, children.Select(f => byId[f.Id]).ToArray());
                    for (int j = 0; j < children.Length; j++) folderTokens[children[j].Id] = tokens[j];
                }
                foreach (var folder in display) {
                    var value = Fields(byId[folder.Id], Copied(FolderPayload.Members));
                    value[StoredSessionCodec.Key.SpaceId] = space[StoredSessionCodec.Key.Id]!.DeepClone();
                    value[SyncPayload.Key.OrderToken] = folderTokens[folder.Id];
                    SyncedText.FolderTitle.Fit(value);
                    SyncedText.FolderSymbol.Fit(value);
                    Add(SyncPayloadType.Folder, value);
                }
            }

            var tabs = portable.Where(t => policy.Includes(Placement(t))).ToArray();
            var tabTokens = Tokens(SyncPayloadType.Tab, tabs);
            for (int j = 0; j < tabs.Length; j++)
                Add(SyncPayloadType.Tab, Tab(tabs[j], space[StoredSessionCodec.Key.Id]!, tabTokens[j], archived: false));
            if (!policy.HistoryAndArchive) continue;
            foreach (var history in Items(space, StoredSessionCodec.Key.History)
                         .Where(h => SyncedAddress.Includes(Text(h![StoredSessionCodec.Key.Url])))) {
                var value = Fields(history!, Copied(HistoryPayload.Members));
                value[StoredSessionCodec.Key.SpaceId] = space[StoredSessionCodec.Key.Id]!.DeepClone();
                Spell(value, StoredSessionCodec.Key.Url);
                Visit(value);
                Add(SyncPayloadType.History, value);
            }
            // Archive presentation sorts by date after a merge. That is not a
            // user reorder: keep accepted positions and append new identities.
            static Guid TabId(JsonNode archived) => Id(archived[StoredSessionCodec.Key.Tab]![StoredSessionCodec.Key.Id]);
            var archive = Items(space, StoredSessionCodec.Key.ArchivedTabs).Where(a => PortableTab(a![StoredSessionCodec.Key.Tab]!)).Select(a => a!)
                .OrderBy(a => existing.GetValueOrDefault(SyncPayloadType.Archive.Kind.RecordName(TabId(a))) ?? "~", StringComparer.Ordinal)
                .ThenBy(a => TabId(a).ToString("D"), StringComparer.Ordinal).ToArray();
            var archiveTokens = Tokens(SyncPayloadType.Archive, archive);
            for (int j = 0; j < archive.Length; j++) Add(SyncPayloadType.Archive, new JsonObject {
                [StoredSessionCodec.Key.Tab] = Tab(archive[j][StoredSessionCodec.Key.Tab]!, space[StoredSessionCodec.Key.Id]!, archiveTokens[j], archived: true),
                [StoredSessionCodec.Key.ArchivedAt] = archive[j][StoredSessionCodec.Key.ArchivedAt]!.DeepClone(),
                [StoredSessionCodec.Key.Reason] = SyncedArchiveReason(archive[j], archiveReasons.GetValueOrDefault(TabId(archive[j])))
            });
        }
        return result;
    }

    private static JsonObject Tab(JsonNode source, JsonNode spaceId, string token, bool archived) {
        // The placement and what it holds are the tab's own as it sits now; a
        // native view never syncs, so its content is never copied.
        var value = Fields(source, StoredSessionCodec.Key.Id, StoredSessionCodec.Key.Title, StoredSessionCodec.Key.Url,
            StoredSessionCodec.Key.Symbol, StoredSessionCodec.Key.LastActivatedAt, StoredSessionCodec.Key.PositionModifiedAt,
            StoredSessionCodec.Key.CustomTitle, StoredSessionCodec.Key.TitleModifiedAt, StoredSessionCodec.Key.KeepsPageLoaded);
        value[StoredSessionCodec.Key.SpaceId] = spaceId.DeepClone();
        value[SyncPayload.Key.OrderToken] = token;
        Spell(value, StoredSessionCodec.Key.Url);
        value[StoredSessionCodec.Key.Placement] = archived
            ? JsonValue.Create(TabPlacement.Current.Name) : source[StoredSessionCodec.Key.Placement]!.DeepClone();
        if (!archived) {
            if (SavedUrl(source) is { } saved) value[StoredSessionCodec.Key.SavedUrl] = new SyncedAddress(saved).Spelled ?? saved;
            // Only a placement that holds folders names one: a pinned tab never does.
            if (source[StoredSessionCodec.Key.FolderId] is { } folder && Placement(source).HoldsFolders)
                value[StoredSessionCodec.Key.FolderId] = folder.DeepClone();
            if (source[StoredSessionCodec.Key.SplitGroupId] is { } split) value[StoredSessionCodec.Key.SplitGroupId] = split.DeepClone();
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
        if (SyncJson.TryInt(value[StoredSessionCodec.Key.VisitCount], out var visits) && visits < 1) value[StoredSessionCodec.Key.VisitCount] = 1;
        if (SyncJson.TryDouble(value[StoredSessionCodec.Key.FirstVisitedAt], out var firstVisited)
            && SyncJson.TryDouble(value[StoredSessionCodec.Key.LastVisitedAt], out var lastVisited) && firstVisited > lastVisited)
            value[StoredSessionCodec.Key.FirstVisitedAt] = value[StoredSessionCodec.Key.LastVisitedAt]!.DeepClone();
    }

    #endregion
}
