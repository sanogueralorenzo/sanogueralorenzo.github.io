using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Maps the existing Swift/CloudKit wire records to engine-independent rules.
/// Unknown payload fields survive; no cloud API or page object crosses here.
public static class NativeSyncEvaluator {
    #region Actions - Sync validation

    private static string Text(JsonNode value, string field) => value[field]!.GetValue<string>();

    internal static double? Date(JsonNode value, string field) {
        if (value[field] is null) return null;
        double date = SyncJson.Double(value[field]!);
        if (!double.IsFinite(date)) throw new BrowserRuleException(BrowserRule.InvalidSyncDate);
        return date;
    }

    private static Guid Id(JsonNode? value) => SyncJson.Identity(value);

    private static SyncVersion Version(JsonNode value)
        => new(SyncJson.ULong(value["version"]!["logicalClock"]!), Id(value["version"]!["deviceID"]));

    private static string Kind(JsonNode value) => Text(value["id"]!, "kind");

    private static string Name(JsonNode value) => Kind(value) + ":" + Id(value["id"]!["value"]).ToString("D");

    private static JsonObject? Payload(JsonNode value) => value["payload"]?["value"]?.AsObject();

    private static SyncRecordStamp Stamp(JsonNode record) {
        var type = SyncPayloadType.Named(Kind(record)) ?? throw new BrowserRuleException(BrowserRule.InvalidSyncKind);
        var payload = Payload(record);
        var tombstone = record["tombstone"];
        if ((payload is null) == (tombstone is null)) throw new BrowserRuleException(BrowserRule.InvalidSyncRecord);
        if (payload is not null && Text(record["payload"]!, "type") != type.Kind.Name)
            throw new BrowserRuleException(BrowserRule.SyncIdentityMismatch);
        var recordId = Id(record["id"]!["value"]);
        var spaceId = Id(record["spaceID"]);
        if (type.Kind.NamesItsSpace && recordId != spaceId) throw new BrowserRuleException(BrowserRule.SyncIdentityMismatch);
        if (payload is not null && (Id(type.Subject(payload)["id"]) != recordId || Id(type.SpaceIdentity(payload)) != spaceId))
            throw new BrowserRuleException(BrowserRule.SyncIdentityMismatch);
        var reason = tombstone is null ? null : SyncDeletionReason.Named(tombstone["reason"]?.GetValue<string>())
            ?? throw new BrowserRuleException(BrowserRule.InvalidSyncDeletion);
        return new(type.Kind, recordId, spaceId, Version(record), reason,
            tombstone is null ? null : Date(tombstone, "deletedAt"), payload is null ? null : type.ActivatedAt(payload));
    }

    internal static void ValidateRecord(JsonObject record) => _ = Stamp(record);

    // Wire identities are UUID values, independent of the writer's letter case.
    // Keep ordinary strings (including UUID-looking titles) case-sensitive.
    // Codable also omits nil fields while the core may emit explicit JSON null.
    internal static bool Equivalent(JsonNode? first, JsonNode? second) => Equivalent(first, second, null);

    private static bool Equivalent(JsonNode? first, JsonNode? second, string? field) {
        if (first is JsonObject a && second is JsonObject b)
            return a.Select(p => p.Key).Union(b.Select(p => p.Key)).All(key =>
                Equivalent(a[key], b[key], key == "value" && a["kind"] is not null ? "id" : key));
        if (first is JsonArray x && second is JsonArray y)
            return x.Count == y.Count && x.Zip(y).All(pair => Equivalent(pair.First, pair.Second, field));
        var kind = SyncWireField.Named(field)?.Kind;
        if (kind == SyncWireField.Kinds.Identity && first is JsonValue av && second is JsonValue bv
            && av.TryGetValue<string>(out var at) && bv.TryGetValue<string>(out var bt)
            && Guid.TryParse(at, out var aid) && Guid.TryParse(bt, out var bid)) return aid == bid;
        // Clocks and other integer fields must retain their full integer
        // precision, so only a timestamp compares as a double.
        if (kind == SyncWireField.Kinds.Timestamp && first is JsonValue ad && second is JsonValue bd
            && SyncJson.TryDouble(ad, out var aDate) && SyncJson.TryDouble(bd, out var bDate)) return aDate == bDate;
        return JsonNode.DeepEquals(first, second);
    }

    internal static TabPlacement Placement(JsonNode payload)
        => TabPlacement.Named(Text(payload, "placement")) ?? throw new BrowserRuleException(BrowserRule.InvalidSyncPlacement);

    /// The record `first` and `second`, two versions of one record, resolve
    /// to: the winner's, with the fields each side last changed. Versions in
    /// different Spaces resolve to the winner's whole, since a field the
    /// other changed, such as a folder, belongs to the Space it left.
    public static JsonObject Resolve(JsonObject first, JsonObject second) {
        var aStamp = Stamp(first); var bStamp = Stamp(second);
        int winner = SyncRecordStamp.Winner(aStamp, bStamp);
        var result = (winner == 0 ? first : second).DeepClone().AsObject();
        var a = Payload(first); var b = Payload(second);
        if (a is null || b is null || aStamp.Space != bStamp.Space) return result;
        SyncPayloadType.Of(first["payload"]!).MergeFields(Payload(result)!, a, b, winner);
        return result;
    }

    /// `records` with each tab that also stands archived kept on the side that
    /// wins: the open tab, or its archive record.
    internal static JsonArray Reconcile(IEnumerable<JsonObject> records) {
        var byId = new Dictionary<string, JsonObject>(StringComparer.Ordinal);
        foreach (var node in records) { _ = Stamp(node!); byId[Name(node!)] = node!.AsObject(); }
        var tabs = SyncPayloadType.Tab;
        foreach (var tab in byId.Values.Where(r => Kind(r) == tabs.Kind.Name && Payload(r) is not null).ToArray()) {
            string archiveName = tabs.Counterpart!.Kind.RecordName(Id(tab["id"]!["value"]));
            if (!byId.TryGetValue(archiveName, out var archiveRecord) || Payload(archiveRecord) is not { } archive) continue;
            var payload = Payload(tab)!;
            bool active = Placement(payload).KeepsTabOverArchive(Date(payload, "lastActivatedAt")!.Value,
                Version(tab), ArchiveReason.Named(Text(archive, "reason")) ?? ArchiveReason.Closed, Date(archive, "archivedAt")!.Value,
                Version(archiveRecord));
            byId.Remove(active ? archiveName : Name(tab));
        }
        return new JsonArray(byId.OrderBy(p => p.Key, StringComparer.Ordinal).Select(p => p.Value.DeepClone()).ToArray());
    }

    #endregion
}
