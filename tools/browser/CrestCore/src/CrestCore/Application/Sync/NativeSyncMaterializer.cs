using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Shared records become a typed session. Where a Space keeps its passwords,
/// native pages and image choices come only from this device; encoding stays
/// at the journal boundary.
public static class NativeSyncMaterializer {
    #region Actions - Materialization

    public static JsonObject Materialize(JsonObject session, JsonNode preferences, IReadOnlyList<JsonObject> records, double now,
        SpaceAccessAuthority? access = null) => StoredSessionCodec.Encode(Materialize(StoredSessionCodec.DecodeSession(session),
            NativeSyncProjection.Preferences(preferences), records.Select(SyncSessionRecord.Read).ToArray(), StoredSessionCodec.Date(now), access));

    internal static SessionState Materialize(SessionState session, SyncPreferences policy, IReadOnlyList<SyncSessionRecord> records,
        DateTimeOffset now, SpaceAccessAuthority? access) {
        var owners = records.Where(record => record.Kind == SyncRecordKind.Folder).ToDictionary(record => record.Id, record => record.SpaceId);
        var deleted = records.Where(record => record.Kind == SyncRecordKind.Folder && record.Tombstone is not null).Select(record => record.Id).ToHashSet();
        var locals = session.Spaces.ToDictionary(space => space.Id);
        var pending = session.SpaceDeletions.Select(deletion => deletion.SpaceId).ToHashSet();
        var brandingIds = records.Where(record => record.Kind == SyncRecordKind.Space && record.SuppliesBranding).Select(record => record.Id).ToHashSet();
        var spaces = new List<SpaceState>();
        var profiles = new HashSet<Guid>();
        foreach (var remote in Payloads<SpacePayload>(records).OrderBy(space => space.OrderToken, StringComparer.Ordinal)
            .ThenBy(space => space.Id.ToString("D"), StringComparer.Ordinal)) {
            if (!profiles.Add(remote.ProfileId)) throw Error(SyncRecordFlaw.SharedProfile, remote.ProfileId);
            locals.TryGetValue(remote.Id, out var local);
            if (local is not null && local.ProfileId != remote.ProfileId) throw Error(SyncRecordFlaw.ProfileChanged, remote.Id);
            if (pending.Contains(remote.Id) && local is not null) { spaces.Add(local); continue; }
            var folders = Folders(remote.Id, records, policy, local, owners, deleted);
            var tabs = Tabs(remote.Id, records, policy, local, folders, owners, deleted);
            var archive = Archive(remote.Id, records, policy, local, tabs);
            var history = History(remote.Id, records, policy, local);
            var localSplitIds = (local?.Tabs ?? []).Where(tab => !Portable(tab) && tab.SplitGroupId is not null)
                .Select(tab => tab.SplitGroupId!.Value).ToHashSet();
            var groups = remote.SplitGroups is { } supplied ? supplied.Select(Group).ToList() : (local?.SplitGroups ?? []).ToList();
            var groupIds = groups.Select(group => group.Id).ToHashSet();
            groups.AddRange((local?.SplitGroups ?? []).Where(group => localSplitIds.Contains(group.Id) && !groupIds.Contains(group.Id)));
            if (tabs.Count == 0) tabs.Add(new(Guid.NewGuid(), TabKind.StartPage.Name, null, null, null, TabKind.StartPage.Symbol,
                null, null, null, TabPlacement.Current, null, null, now, null, null, null, false));
            var (credentials, credentialsModifiedAt) = CredentialPreferences(local, remote);
            var (accessPolicy, accessModifiedAt) = AccessPolicy(local, remote, access);
            var settings = new SpaceSettings(remote.Name, remote.Symbol, remote.Accent, brandingIds.Contains(remote.Id) ? remote.Branding : null, remote.BrowsingPreferences,
                credentials, accessPolicy, remote.IsSavedTabsExpanded, remote.SavedTabsExpansionModifiedAt?.Moment,
                credentialsModifiedAt, accessModifiedAt);
            spaces.Add(new(remote.Id, remote.ProfileId, settings, folders, tabs, groups, archive, history));
        }
        foreach (var id in pending.Where(id => spaces.All(space => space.Id != id))) {
            var local = locals[id];
            if (!profiles.Add(local.ProfileId)) throw Error(SyncRecordFlaw.SharedProfile, local.ProfileId);
            spaces.Add(local);
        }
        return spaces.Count == 0 ? session : session with { Spaces = spaces, DisposableSeedMarker = null };
    }

    private static IEnumerable<T> Payloads<T>(IReadOnlyList<SyncSessionRecord> records, Guid? space = null) where T : SyncPayload =>
        records.Where(record => space is null || record.SpaceId == space).Select(record => record.Payload).OfType<T>();

    private static bool Portable(TabState tab) => SyncedAddress.IncludesTab(tab.Url, tab.NativeContent is not null,
        tab.SavedUrl ?? (tab.Placement.IsDurable ? tab.Url : null));

    private static bool Portable(TabPayload tab) => SyncedAddress.IncludesTab(tab.Url?.Text, tab.NativeContent is not null,
        tab.SavedUrl?.Text ?? (tab.Placement.IsDurable ? tab.Url?.Text : null));

    private static Dictionary<Guid, FolderState> LocalFolders(SpaceState? local) => (local?.Folders ?? []).ToDictionary(folder => folder.Id);

    private static SyncRecordsFlawedException Error(SyncRecordFlaw flaw, Guid subject) => new(flaw, subject);

    /// Whether the Space uses Crest Passwords, and when someone chose, come from
    /// the record once someone chose; where it keeps them only from this device.
    private static (CredentialPreferences Preferences, DateTimeOffset? ModifiedAt) CredentialPreferences(SpaceState? local, SpacePayload remote) {
        var kept = local?.Settings.CredentialPreferences ?? StoredSessionCodec.DefaultCredentialPreferences;
        return remote is { CredentialsEnabled: { } enabled, CredentialsEnabledModifiedAt: { } modifiedAt }
            ? (kept with { IsEnabled = enabled }, modifiedAt.Moment)
            : (kept, local?.Settings.CredentialsEnabledModifiedAt);
    }

    /// Who may open the Space, and when someone chose. The later choice wins on
    /// every device, since the device that made it authenticated for it, and
    /// its time keeps a stale copy from undoing a newer one. Where neither is
    /// later, as for a record from before locks carried their time, raising
    /// protection always applies and removing it requires this device's grant;
    /// the next upload restores the guarded policy when it was refused.
    private static (SpaceAccessPolicy Policy, DateTimeOffset? ModifiedAt) AccessPolicy(SpaceState? local, SpacePayload remote,
        SpaceAccessAuthority? access) {
        var chosen = remote.AccessPolicyModifiedAt?.Moment;
        if (local is null) return (remote.AccessPolicy, chosen);
        var kept = local.Settings.AccessPolicyModifiedAt;
        if (chosen is { } remoteChoice && (kept is null || remoteChoice > kept)) return (remote.AccessPolicy, chosen);
        if (chosen is not null && kept > chosen) return (local.Settings.AccessPolicy, kept);
        if (local.Settings.AccessPolicy == SpaceAccessPolicy.Open || remote.AccessPolicy != SpaceAccessPolicy.Open)
            return (remote.AccessPolicy, kept);
        if (access is not null) {
            lock (access) {
                if (!access.IsLocked(new(remote.Id, remote.ProfileId), true)) return (remote.AccessPolicy, kept);
            }
        }
        return (local.Settings.AccessPolicy, kept);
    }

    private static SplitGroupState Group(SplitGroupPayload group) => new(group.Id, group.CustomTitle, group.TitleModifiedAt?.Moment,
        group.CustomIconSymbol, group.IconModifiedAt?.Moment, group.Tint, group.TintModifiedAt?.Moment);

    #endregion

    #region Actions - Folders and tabs

    private static List<FolderState> Folders(Guid space, IReadOnlyList<SyncSessionRecord> records, SyncPreferences policy, SpaceState? local,
        IReadOnlyDictionary<Guid, Guid> owners, HashSet<Guid> deleted) {
        var colorIds = records.Where(record => record.Kind == SyncRecordKind.Folder && record.SuppliesFolderColor).Select(record => record.Id).ToHashSet();
        var synced = Payloads<FolderPayload>(records, space).Where(folder => policy.Includes(folder.Location))
            .OrderBy(folder => folder.OrderToken, StringComparer.Ordinal).ThenBy(folder => folder.Id.ToString("D"), StringComparer.Ordinal)
            .Select(folder => new FolderState(folder.Id, folder.Location, folder.Title, folder.Symbol, colorIds.Contains(folder.Id) ? folder.Color : null, folder.ParentId,
                folder.IsCollapsed, folder.CollapseModifiedAt?.Moment, folder.OrderAnchorTabId)).ToArray();
        IReadOnlyList<FolderState> resolved;
        try { resolved = FolderTree.Materialized(space, synced, owners, LocalFolders(local), deleted); } catch (BrowserRuleException) { throw Error(SyncRecordFlaw.InvalidFolderHierarchy, space); }
        var included = resolved.Select(folder => folder.Id).ToHashSet();
        return [.. resolved, .. (local?.Folders ?? []).Where(folder => !included.Contains(folder.Id) && !policy.Includes(folder.Location))];
    }

    private static TabState Tab(TabPayload remote, TabState? local, bool archived = false) => new(remote.Id, remote.Title,
        remote.Url is { } url ? url.Spelled ?? url.Text : null, remote.NativeContent,
        !archived && remote.Placement.IsDurable ? remote.SavedUrl?.Spelled ?? remote.SavedUrl?.Text ?? remote.Url?.Spelled ?? remote.Url?.Text : null,
        remote.Symbol, local?.FaviconUrl, local?.IconAccent, local?.StoredIconMode, archived ? TabPlacement.Current : remote.Placement,
        null, archived ? null : remote.SplitGroupId, remote.LastActivatedAt.Moment, remote.PositionModifiedAt?.Moment,
        remote.CustomTitle, remote.TitleModifiedAt?.Moment, remote.KeepsPageLoaded);

    private static List<TabState> Tabs(Guid space, IReadOnlyList<SyncSessionRecord> records, SyncPreferences policy, SpaceState? local,
        IReadOnlyList<FolderState> folders, IReadOnlyDictionary<Guid, Guid> owners, HashSet<Guid> deleted) {
        var locals = local?.Tabs ?? [];
        var localOnly = locals.Select((tab, index) => (tab, index)).Where(item => !Portable(item.tab)).ToArray();
        var localOnlyIds = localOnly.Select(item => item.tab.Id).Concat((local?.ArchivedTabs ?? [])
            .Where(archived => !Portable(archived.Tab)).Select(archived => archived.Tab.Id)).ToHashSet();
        var synced = Payloads<TabPayload>(records, space).Where(tab => Portable(tab) && !localOnlyIds.Contains(tab.Id) && policy.Includes(tab.Placement))
            .OrderBy(tab => tab.OrderToken, StringComparer.Ordinal).ThenBy(tab => tab.Id.ToString("D"), StringComparer.Ordinal)
            .OrderBy(tab => tab.Placement.Rank).ToArray();
        var syncedIds = synced.Select(tab => tab.Id).ToHashSet();
        var result = locals.Where(tab => Portable(tab) && !policy.Includes(tab.Placement) && !syncedIds.Contains(tab.Id)).ToList();
        var byId = locals.ToDictionary(tab => tab.Id);
        var folderIds = folders.Select(folder => folder.Id).ToHashSet();
        var localFolders = LocalFolders(local);
        foreach (var remote in synced) {
            var folder = remote.FolderId;
            if (remote.Placement.HoldsFolders && folder is { } missing && !folderIds.Contains(missing)) {
                if (owners.TryGetValue(missing, out var owner) && owner != space) throw Error(SyncRecordFlaw.DanglingFolder, remote.Id);
                if (!FolderTree.TryPromote(missing, folderIds, localFolders, deleted, out folder)) continue;
            }
            result.Add(Tab(remote, byId.GetValueOrDefault(remote.Id)) with { FolderId = remote.Placement.HoldsFolders ? folder : null });
        }
        if (!TabPlacement.All.All(placement => placement.Holds(result.Count(tab => tab.Placement == placement))))
            throw Error(SyncRecordFlaw.TooManyPinnedTabs, space);
        foreach (var (tab, index) in localOnly) result.Insert(Math.Min(index, result.Count), tab);
        return result;
    }

    #endregion

    #region Actions - Archive and history

    private static List<ArchivedTabState> Archive(Guid space, IReadOnlyList<SyncSessionRecord> records, SyncPreferences policy, SpaceState? local,
        IReadOnlyList<TabState> tabs) {
        if (!policy.HistoryAndArchive) return [.. local?.ArchivedTabs ?? []];
        var active = tabs.Select(tab => tab.Id).ToHashSet();
        var byId = (local?.ArchivedTabs ?? []).ToDictionary(archived => archived.Tab.Id);
        var localOnly = byId.Values.Where(archived => !Portable(archived.Tab) && !active.Contains(archived.Tab.Id)).ToArray();
        var localOnlyIds = localOnly.Select(archived => archived.Tab.Id).ToHashSet();
        var remote = Payloads<ArchivePayload>(records, space).Where(archived => Portable(archived.Tab)
            && !localOnlyIds.Contains(archived.Tab.Id) && !active.Contains(archived.Tab.Id))
            .OrderBy(archived => archived.Tab.OrderToken, StringComparer.Ordinal).ThenBy(archived => archived.Id.ToString("D"), StringComparer.Ordinal);
        var result = remote.Select(archived => {
            byId.TryGetValue(archived.Id, out var previous);
            return new ArchivedTabState(Tab(archived.Tab, previous?.Tab, archived: true), archived.ArchivedAt.Moment,
                previous?.Reason ?? ArchiveReason.Received(archived.Reason.IsExplicitDeletion));
        }).ToList();
        var projected = result.Select(archived => archived.Tab.Id).ToHashSet();
        var localTabs = (local?.Tabs ?? []).Where(Portable).ToDictionary(tab => tab.Id);
        foreach (var record in records.Where(record => record.Kind == SyncRecordKind.Tab && record.SpaceId == space
            && record.Tombstone?.Reason.IsExplicit == true)) {
            if (projected.Contains(record.Id) || !localTabs.TryGetValue(record.Id, out var tab)) continue;
            result.Add(new(tab with { Placement = TabPlacement.Current, FolderId = null, SavedUrl = null, SplitGroupId = null },
                record.Tombstone!.DeletedAt.Moment, ArchiveReason.Received(explicitDeletion: true)));
        }
        return [.. result.Concat(localOnly).OrderByDescending(archived => archived.ArchivedAt)];
    }

    private static List<HistoryEntryState> History(Guid space, IReadOnlyList<SyncSessionRecord> records, SyncPreferences policy, SpaceState? local) {
        if (!policy.HistoryAndArchive) return [.. local?.History ?? []];
        var localOnly = (local?.History ?? []).Where(entry => !SyncedAddress.Includes(entry.Url)).ToArray();
        var localIds = localOnly.Select(entry => entry.Id).ToHashSet();
        var synced = Payloads<HistoryPayload>(records, space).Where(entry => SyncedAddress.Includes(entry.Url.Text) && !localIds.Contains(entry.Id))
            .OrderByDescending(entry => entry.LastVisitedAt.ReferenceSeconds).ThenBy(entry => entry.Id.ToString("D"), StringComparer.Ordinal)
            .Take(HistoryEntryState.MaximumEntries).Select(entry => new HistoryEntryState(entry.Id, entry.Url.Spelled ?? entry.Url.Text, entry.Title,
                entry.FirstVisitedAt.Moment, entry.LastVisitedAt.Moment, checked((int)entry.VisitCount)));
        return [.. synced.Concat(localOnly).OrderByDescending(entry => entry.LastVisitedAt)];
    }

    #endregion
}
