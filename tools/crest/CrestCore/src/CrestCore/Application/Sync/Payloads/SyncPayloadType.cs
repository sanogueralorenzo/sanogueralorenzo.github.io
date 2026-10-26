using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// A kind of payload the journal and the cloud carry: how its value is read,
/// and the rules the journal applies to a value of the kind as it holds it.
/// A payload names its type by its kind's name.
internal abstract class SyncPayloadType {
    #region Static Variables

    public static readonly SyncPayloadType Space = new SpaceType();
    public static readonly SyncPayloadType Folder = new FolderType();
    public static readonly SyncPayloadType Tab = new TabType();
    public static readonly SyncPayloadType History = new HistoryType();
    public static readonly SyncPayloadType Archive = new ArchiveType();

    public static IReadOnlyList<SyncPayloadType> All { get; } = [Space, Folder, Tab, History, Archive];

    #endregion

    #region Variables

    /// The kind of record a payload of this type is.
    public SyncRecordKind Kind { get; }

    /// Reads a payload's value.
    private readonly Func<SyncPayloadReader, SyncPayload> read;

    /// The type whose records hold the same tab as a record of this type, or
    /// null for a type that holds no tab another type also holds.
    public virtual SyncPayloadType? Counterpart => null;

    #endregion

    #region Constructors

    private SyncPayloadType(SyncRecordKind kind, Func<SyncPayloadReader, SyncPayload> read) {
        Kind = kind;
        this.read = read;
    }

    #endregion

    #region Actions - Reading

    /// The type a payload spells `name`, or null when no client knows one.
    public static SyncPayloadType? Named(string? name) => All.FirstOrDefault(type => type.Kind.Name == name);

    /// The type of `payload`, a `{"type", "value"}` envelope as the journal
    /// holds it. Throws `BrowserRuleException` for a type no client knows.
    public static SyncPayloadType Of(JsonNode payload) =>
        Named(payload[SyncPayload.Key.Type]?.GetValue<string>()) ?? throw new BrowserRuleException(BrowserRule.InvalidSyncKind);

    /// The payload `value` holds. Throws `UnreadableSyncPayloadException` for
    /// one no client reads.
    public SyncPayload Read(SyncPayloadReader value) => read(value);

    #endregion

    #region Actions - Journal rules

    /// The object in `value` that carries the record's identity and Space.
    public virtual JsonObject Subject(JsonObject value) => value;

    /// The identity of the Space the record `value` belongs to.
    public JsonNode SpaceIdentity(JsonObject value) =>
        Subject(value)[Kind.NamesItsSpace ? StoredSessionCodec.Key.Id : StoredSessionCodec.Key.SpaceId]!;

    /// Whether the sync category `preferences` syncs `value`.
    public virtual bool SyncsUnder(JsonNode preferences, JsonObject value) => preferences["historyAndArchive"]!.GetValue<bool>();

    /// Whether every device can take `value`: one naming an address only this
    /// device opens stays on it.
    public virtual bool IsPortable(JsonObject value) => true;

    /// The folder `value` sits in, or null when it sits in none.
    public virtual JsonNode? ParentFolder(JsonObject value) => null;

    /// When `value`'s tab was last shown, which a later deletion must not
    /// outrank, or null for a value that is not an open tab.
    public virtual double? ActivatedAt(JsonObject value) => null;

    /// Merges into `result`, a copy of the winning value, the fields each side
    /// of a conflict between `first` and `second` last changed; `winner` is 0
    /// when `first` won.
    public virtual void MergeFields(JsonObject result, JsonObject first, JsonObject second, int winner) {
    }

    /// The reason the record `value` is deleted for once the staged session no
    /// longer holds it, or null when its absence authorizes nothing.
    /// `archiveReason` is why its tab was archived, `owningSpaceRemains` whether
    /// its Space stays, and `removal` the reason of the edit that removed it.
    public virtual SyncDeletionReason? DeletionReason(JsonObject value, ArchiveReason? archiveReason, bool owningSpaceRemains,
        SyncDeletionReason removal) => removal;

    /// The value of this type that holds `tab`, the tab a record of the
    /// counterpart type holds.
    public virtual JsonObject Holding(JsonNode tab) => throw new InvalidOperationException($"A {Kind.Name} holds no tab.");

    #endregion

    #region Actions - Merging

    private static void Copy(JsonObject to, JsonObject from, params string[] fields) {
        foreach (string field in fields) {
            if (from.TryGetPropertyValue(field, out var value)) to[field] = value?.DeepClone();
            else to.Remove(field);
        }
    }

    /// Copies `fields` and `timestamp` into `result` from whichever of `first`
    /// and `second` changed them last.
    private static void LatestFields(JsonObject result, JsonObject first, JsonObject second, string timestamp, params string[] fields) {
        if (SyncRecordStamp.Later(NativeSyncEvaluator.Date(first, timestamp), NativeSyncEvaluator.Date(second, timestamp)) is not { } winner)
            return;
        var source = winner == 0 ? first : second;
        Copy(result, source, fields);
        Copy(result, source, timestamp);
    }

    private static JsonNode? MergeGroups(JsonArray? first, JsonArray? second, int winner) {
        if (first is null || second is null) return (first ?? second)?.DeepClone();
        var preferred = winner == 0 ? first : second;
        var fallback = (winner == 0 ? second : first)
            .ToDictionary(n => SyncJson.Identity(n![StoredSessionCodec.Key.Id]), n => n!.AsObject());
        return new JsonArray(preferred.Select(n => {
            var group = n!.DeepClone().AsObject();
            if (fallback.TryGetValue(SyncJson.Identity(group[StoredSessionCodec.Key.Id]), out var older)) {
                LatestFields(group, n.AsObject(), older, StoredSessionCodec.Key.TitleModifiedAt, StoredSessionCodec.Key.CustomTitle);
                LatestFields(group, n.AsObject(), older, StoredSessionCodec.Key.IconModifiedAt, StoredSessionCodec.Key.CustomIconSymbol);
                LatestFields(group, n.AsObject(), older, StoredSessionCodec.Key.TintModifiedAt, StoredSessionCodec.Key.Tint);
            }
            return (JsonNode)group;
        }).ToArray());
    }

    /// Whether every device can take a tab that `tab`, a tab's value, holds.
    private static bool PortableTab(JsonNode tab) => SyncedAddress.IncludesTab(tab[StoredSessionCodec.Key.Url]?.GetValue<string>(),
        tab[StoredSessionCodec.Key.NativeContent] is not null, tab[StoredSessionCodec.Key.SavedUrl]?.GetValue<string>());

    /// Whether `preferences` syncs a value placed where `value[member]` says:
    /// the current tabs, or the saved structure.
    private static bool SyncsPlaced(JsonNode preferences, JsonObject value, string member) =>
        preferences[TabPlacement.Named(value[member]!.GetValue<string>())?.IsDurable == false ? "currentTabs" : "savedStructure"]!
            .GetValue<bool>();

    #endregion

    #region Types

    private sealed class SpaceType() : SyncPayloadType(SyncRecordKind.Space, SpacePayload.Read) {
        public override bool SyncsUnder(JsonNode preferences, JsonObject value) => true;

        /// A Space merges each choice someone made with a clock to its later
        /// side, and its splits' metadata field by field.
        public override void MergeFields(JsonObject result, JsonObject first, JsonObject second, int winner) {
            LatestFields(result, first, second, StoredSessionCodec.Key.SavedTabsExpansionModifiedAt, StoredSessionCodec.Key.IsSavedTabsExpanded);
            LatestFields(result, first, second, StoredSessionCodec.Key.CredentialsEnabledModifiedAt, SyncPayload.Key.CredentialsEnabled);
            LatestFields(result, first, second, StoredSessionCodec.Key.AccessPolicyModifiedAt, StoredSessionCodec.Key.AccessPolicy);
            const string groups = StoredSessionCodec.Key.SplitGroups;
            result[groups] = MergeGroups(first[groups] as JsonArray, second[groups] as JsonArray, winner);
        }

        public override SyncDeletionReason? DeletionReason(JsonObject value, ArchiveReason? archiveReason, bool owningSpaceRemains,
            SyncDeletionReason removal) => removal.ForStructure;
    }

    private sealed class FolderType() : SyncPayloadType(SyncRecordKind.Folder, FolderPayload.Read) {
        public override bool SyncsUnder(JsonNode preferences, JsonObject value) =>
            SyncsPlaced(preferences, value, StoredSessionCodec.Key.Location);

        public override JsonNode? ParentFolder(JsonObject value) => value[StoredSessionCodec.Key.ParentId];

        public override void MergeFields(JsonObject result, JsonObject first, JsonObject second, int winner) =>
            LatestFields(result, first, second, StoredSessionCodec.Key.CollapseModifiedAt, StoredSessionCodec.Key.IsCollapsed);

        public override SyncDeletionReason? DeletionReason(JsonObject value, ArchiveReason? archiveReason, bool owningSpaceRemains,
            SyncDeletionReason removal) => removal.ForStructure;
    }

    private sealed class TabType() : SyncPayloadType(SyncRecordKind.Tab, TabPayload.Read) {
        public override SyncPayloadType Counterpart => Archive;

        public override bool SyncsUnder(JsonNode preferences, JsonObject value) =>
            SyncsPlaced(preferences, value, StoredSessionCodec.Key.Placement);

        public override bool IsPortable(JsonObject value) => PortableTab(value);

        public override JsonNode? ParentFolder(JsonObject value) =>
            TabPlacement.Named(value[StoredSessionCodec.Key.Placement]!.GetValue<string>())?.HoldsFolders != false
                ? value[StoredSessionCodec.Key.FolderId] : null;

        public override double? ActivatedAt(JsonObject value) => NativeSyncEvaluator.Date(value, StoredSessionCodec.Key.LastActivatedAt);

        /// A tab merges to its latest showing, the position its later move
        /// gave it (or the placement both sides keep), and its later rename.
        public override void MergeFields(JsonObject result, JsonObject first, JsonObject second, int winner) {
            const string activated = StoredSessionCodec.Key.LastActivatedAt, moved = StoredSessionCodec.Key.PositionModifiedAt;
            const string placed = StoredSessionCodec.Key.Placement, folder = StoredSessionCodec.Key.FolderId;
            const string split = StoredSessionCodec.Key.SplitGroupId;
            result[activated] = Math.Max(NativeSyncEvaluator.Date(first, activated)!.Value, NativeSyncEvaluator.Date(second, activated)!.Value);
            if (SyncRecordStamp.Later(NativeSyncEvaluator.Date(first, moved), NativeSyncEvaluator.Date(second, moved)) is { } position) {
                var source = position == 0 ? first : second;
                Copy(result, source, placed, folder, SyncPayload.Key.OrderToken, moved, split);
                if (!NativeSyncEvaluator.Placement(source).HoldsFolders) result.Remove(folder);
                if (!NativeSyncEvaluator.Placement(source).HoldsSplits) result.Remove(split);
            } else {
                var placement = NativeSyncEvaluator.Placement(first).Retained(NativeSyncEvaluator.Placement(second));
                result[placed] = placement.Name;
                if (!placement.HoldsFolders) result.Remove(folder);
                else result[folder] ??= (first[folder] ?? second[folder])?.DeepClone();
                result[split] ??= (first[split] ?? second[split])?.DeepClone();
            }
            LatestFields(result, first, second, StoredSessionCodec.Key.TitleModifiedAt, StoredSessionCodec.Key.CustomTitle);
        }

        public override SyncDeletionReason? DeletionReason(JsonObject value, ArchiveReason? archiveReason, bool owningSpaceRemains,
            SyncDeletionReason removal) => removal.ForTab(NativeSyncEvaluator.Placement(value), archiveReason,
            owningSpaceRemains);

        public override JsonObject Holding(JsonNode tab) => tab.DeepClone().AsObject();
    }

    private sealed class HistoryType() : SyncPayloadType(SyncRecordKind.History, HistoryPayload.Read) {
        public override bool IsPortable(JsonObject value) => SyncedAddress.Includes(value[StoredSessionCodec.Key.Url]?.GetValue<string>());

        /// A visit merges to the earliest first visit, the latest last visit
        /// and the larger count.
        public override void MergeFields(JsonObject result, JsonObject first, JsonObject second, int winner) {
            const string firstVisited = StoredSessionCodec.Key.FirstVisitedAt, lastVisited = StoredSessionCodec.Key.LastVisitedAt;
            const string visits = StoredSessionCodec.Key.VisitCount;
            result[firstVisited] = Math.Min(NativeSyncEvaluator.Date(first, firstVisited)!.Value, NativeSyncEvaluator.Date(second, firstVisited)!.Value);
            result[lastVisited] = Math.Max(NativeSyncEvaluator.Date(first, lastVisited)!.Value, NativeSyncEvaluator.Date(second, lastVisited)!.Value);
            result[visits] = Math.Max(SyncJson.Int(first[visits]!), SyncJson.Int(second[visits]!));
        }
    }

    private sealed class ArchiveType() : SyncPayloadType(SyncRecordKind.Archive, ArchivePayload.Read) {
        public override SyncPayloadType Counterpart => Tab;

        public override JsonObject Subject(JsonObject value) => value[StoredSessionCodec.Key.Tab]!.AsObject();

        public override bool IsPortable(JsonObject value) => PortableTab(Subject(value));

        public override JsonObject Holding(JsonNode tab) => new() { [StoredSessionCodec.Key.Tab] = tab.DeepClone() };
    }

    #endregion
}
