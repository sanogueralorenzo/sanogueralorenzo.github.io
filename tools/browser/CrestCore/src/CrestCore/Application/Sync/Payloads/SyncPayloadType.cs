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
        Named(payload["type"]?.GetValue<string>()) ?? throw new BrowserRuleException(BrowserRule.InvalidSyncKind);

    /// The payload `value` holds. Throws `UnreadableSyncPayloadException` for
    /// one no client reads.
    public SyncPayload Read(SyncPayloadReader value) => read(value);

    #endregion

    #region Actions - Journal rules

    /// The object in `value` that carries the record's identity and Space.
    public virtual JsonObject Subject(JsonObject value) => value;

    /// The identity of the Space the record `value` belongs to.
    public JsonNode SpaceIdentity(JsonObject value) => Subject(value)[Kind.NamesItsSpace ? "id" : "spaceID"]!;

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
        var fallback = (winner == 0 ? second : first).ToDictionary(n => SyncJson.Identity(n!["id"]), n => n!.AsObject());
        return new JsonArray(preferred.Select(n => {
            var group = n!.DeepClone().AsObject();
            if (fallback.TryGetValue(SyncJson.Identity(group["id"]), out var older)) {
                LatestFields(group, n.AsObject(), older, "titleModifiedAt", "customTitle");
                LatestFields(group, n.AsObject(), older, "iconModifiedAt", "customIconSymbol");
                LatestFields(group, n.AsObject(), older, "tintModifiedAt", "tint");
            }
            return (JsonNode)group;
        }).ToArray());
    }

    /// Whether every device can take a tab that `tab`, a tab's value, holds.
    private static bool PortableTab(JsonNode tab) => SyncedAddress.IncludesTab(tab["url"]?.GetValue<string>(),
        tab["nativeContent"] is not null, tab["savedURL"]?.GetValue<string>());

    /// Whether `preferences` syncs a value placed where `value[member]` says:
    /// the current tabs, or the saved structure.
    private static bool SyncsPlaced(JsonNode preferences, JsonObject value, string member) =>
        preferences[TabPlacement.Named(value[member]!.GetValue<string>())?.IsDurable == false ? "currentTabs" : "savedStructure"]!
            .GetValue<bool>();

    #endregion

    #region Types

    private sealed class SpaceType() : SyncPayloadType(SyncRecordKind.Space, SpacePayload.Read) {
        public override bool SyncsUnder(JsonNode preferences, JsonObject value) => true;

        public override void MergeFields(JsonObject result, JsonObject first, JsonObject second, int winner) {
            LatestFields(result, first, second, "savedTabsExpansionModifiedAt", "isSavedTabsExpanded");
            LatestFields(result, first, second, "credentialsEnabledModifiedAt", "credentialsEnabled");
            LatestFields(result, first, second, "accessPolicyModifiedAt", "accessPolicy");
            result["splitGroups"] = MergeGroups(first["splitGroups"] as JsonArray, second["splitGroups"] as JsonArray, winner);
        }

        public override SyncDeletionReason? DeletionReason(JsonObject value, ArchiveReason? archiveReason, bool owningSpaceRemains,
            SyncDeletionReason removal) => removal.ForStructure;
    }

    private sealed class FolderType() : SyncPayloadType(SyncRecordKind.Folder, FolderPayload.Read) {
        public override bool SyncsUnder(JsonNode preferences, JsonObject value) => SyncsPlaced(preferences, value, "location");

        public override JsonNode? ParentFolder(JsonObject value) => value["parentID"];

        public override void MergeFields(JsonObject result, JsonObject first, JsonObject second, int winner) =>
            LatestFields(result, first, second, "collapseModifiedAt", "isCollapsed");

        public override SyncDeletionReason? DeletionReason(JsonObject value, ArchiveReason? archiveReason, bool owningSpaceRemains,
            SyncDeletionReason removal) => removal.ForStructure;
    }

    private sealed class TabType() : SyncPayloadType(SyncRecordKind.Tab, TabPayload.Read) {
        public override SyncPayloadType Counterpart => Archive;

        public override bool SyncsUnder(JsonNode preferences, JsonObject value) => SyncsPlaced(preferences, value, "placement");

        public override bool IsPortable(JsonObject value) => PortableTab(value);

        public override JsonNode? ParentFolder(JsonObject value) =>
            TabPlacement.Named(value["placement"]!.GetValue<string>())?.HoldsFolders != false ? value["folderID"] : null;

        public override double? ActivatedAt(JsonObject value) => NativeSyncEvaluator.Date(value, "lastActivatedAt");

        public override void MergeFields(JsonObject result, JsonObject first, JsonObject second, int winner) {
            result["lastActivatedAt"] = Math.Max(NativeSyncEvaluator.Date(first, "lastActivatedAt")!.Value,
                NativeSyncEvaluator.Date(second, "lastActivatedAt")!.Value);
            if (SyncRecordStamp.Later(NativeSyncEvaluator.Date(first, "positionModifiedAt"),
                    NativeSyncEvaluator.Date(second, "positionModifiedAt")) is { } position) {
                var source = position == 0 ? first : second;
                Copy(result, source, "placement", "folderID", "orderToken", "positionModifiedAt", "splitGroupID");
                if (!NativeSyncEvaluator.Placement(source).HoldsFolders) result.Remove("folderID");
                if (!NativeSyncEvaluator.Placement(source).HoldsSplits) result.Remove("splitGroupID");
            } else {
                var placement = NativeSyncEvaluator.Placement(first).Retained(NativeSyncEvaluator.Placement(second));
                result["placement"] = placement.Name;
                if (!placement.HoldsFolders) result.Remove("folderID");
                else result["folderID"] ??= (first["folderID"] ?? second["folderID"])?.DeepClone();
                result["splitGroupID"] ??= (first["splitGroupID"] ?? second["splitGroupID"])?.DeepClone();
            }
            LatestFields(result, first, second, "titleModifiedAt", "customTitle");
        }

        public override SyncDeletionReason? DeletionReason(JsonObject value, ArchiveReason? archiveReason, bool owningSpaceRemains,
            SyncDeletionReason removal) => removal.ForTab(NativeSyncEvaluator.Placement(value), archiveReason,
            owningSpaceRemains);

        public override JsonObject Holding(JsonNode tab) => tab.DeepClone().AsObject();
    }

    private sealed class HistoryType() : SyncPayloadType(SyncRecordKind.History, HistoryPayload.Read) {
        public override bool IsPortable(JsonObject value) => SyncedAddress.Includes(value["url"]?.GetValue<string>());

        public override void MergeFields(JsonObject result, JsonObject first, JsonObject second, int winner) {
            result["firstVisitedAt"] = Math.Min(NativeSyncEvaluator.Date(first, "firstVisitedAt")!.Value,
                NativeSyncEvaluator.Date(second, "firstVisitedAt")!.Value);
            result["lastVisitedAt"] = Math.Max(NativeSyncEvaluator.Date(first, "lastVisitedAt")!.Value,
                NativeSyncEvaluator.Date(second, "lastVisitedAt")!.Value);
            result["visitCount"] = Math.Max(SyncJson.Int(first["visitCount"]!), SyncJson.Int(second["visitCount"]!));
        }
    }

    private sealed class ArchiveType() : SyncPayloadType(SyncRecordKind.Archive, ArchivePayload.Read) {
        public override SyncPayloadType Counterpart => Tab;

        public override JsonObject Subject(JsonObject value) => value["tab"]!.AsObject();

        public override bool IsPortable(JsonObject value) => PortableTab(Subject(value));

        public override JsonObject Holding(JsonNode tab) => new() { ["tab"] = tab.DeepClone() };
    }

    #endregion
}
