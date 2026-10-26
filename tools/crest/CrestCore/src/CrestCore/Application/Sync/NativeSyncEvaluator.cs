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

    /// The value of `record`'s payload, or null for a tombstone or a payload
    /// without one.
    private static JsonObject? PayloadValue(SyncJournalRecord record) => record.Payload?[SyncPayload.Key.Value]?.AsObject();

    private static SyncRecordStamp Stamp(SyncJournalRecord record) {
        var type = SyncPayloadType.Named(record.KindName) ?? throw new BrowserRuleException(BrowserRule.InvalidSyncKind);
        var payload = PayloadValue(record);
        var tombstone = record.Tombstone;
        if ((payload is null) == (tombstone is null)) throw new BrowserRuleException(BrowserRule.InvalidSyncRecord);
        if (payload is not null && Text(record.Payload!, SyncPayload.Key.Type) != type.Kind.Name)
            throw new BrowserRuleException(BrowserRule.SyncIdentityMismatch);
        var recordId = record.Id;
        var spaceId = record.SpaceId;
        if (type.Kind.NamesItsSpace && recordId != spaceId) throw new BrowserRuleException(BrowserRule.SyncIdentityMismatch);
        if (payload is not null
            && (Id(type.Subject(payload)[StoredSessionCodec.Key.Id]) != recordId || Id(type.SpaceIdentity(payload)) != spaceId))
            throw new BrowserRuleException(BrowserRule.SyncIdentityMismatch);
        var reason = tombstone is null ? null : SyncDeletionReason.Named(tombstone[SyncJournalRecord.Key.Reason]?.GetValue<string>())
            ?? throw new BrowserRuleException(BrowserRule.InvalidSyncDeletion);
        return new(type.Kind, recordId, spaceId, record.Version, reason,
            tombstone is null ? null : Date(tombstone, SyncJournalRecord.Key.DeletedAt), payload is null ? null : type.ActivatedAt(payload));
    }

    internal static void ValidateRecord(JsonObject record) => _ = Stamp(new(record));

    // Wire identities are UUID values, independent of the writer's letter case.
    // Keep ordinary strings (including UUID-looking titles) case-sensitive.
    // Codable also omits nil fields while the core may emit explicit JSON null.
    internal static bool Equivalent(JsonNode? first, JsonNode? second) => Equivalent(first, second, null);

    private static bool Equivalent(JsonNode? first, JsonNode? second, string? field) {
        if (first is JsonObject a && second is JsonObject b)
            return a.Select(p => p.Key).Union(b.Select(p => p.Key)).All(key =>
                Equivalent(a[key], b[key],
                    key == SyncJournalRecord.Key.Value && a[SyncJournalRecord.Key.Kind] is not null ? SyncJournalRecord.Key.Id : key));
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
        => TabPlacement.Named(Text(payload, StoredSessionCodec.Key.Placement)) ?? throw new BrowserRuleException(BrowserRule.InvalidSyncPlacement);

    /// The record `first` and `second`, two versions of one record, resolve
    /// to: the winner's, with the fields each side last changed. Versions in
    /// different Spaces resolve to the winner's whole, since a field the
    /// other changed, such as a folder, belongs to the Space it left.
    public static JsonObject Resolve(JsonObject first, JsonObject second) {
        var aStamp = Stamp(new(first)); var bStamp = Stamp(new(second));
        int winner = SyncRecordStamp.Winner(aStamp, bStamp);
        var result = (winner == 0 ? first : second).DeepClone().AsObject();
        var a = PayloadValue(new(first)); var b = PayloadValue(new(second));
        if (a is null || b is null || aStamp.Space != bStamp.Space) return result;
        SyncPayloadType.Of(new SyncJournalRecord(first).Payload!).MergeFields(PayloadValue(new(result))!, a, b, winner);
        return result;
    }

    /// `records` with each tab that also stands archived kept on the side that
    /// wins: the open tab, or its archive record.
    internal static JsonArray Reconcile(IEnumerable<JsonObject> records) {
        var byId = new Dictionary<string, SyncJournalRecord>(StringComparer.Ordinal);
        foreach (var node in records) {
            var record = new SyncJournalRecord(node);
            _ = Stamp(record);
            byId[record.Name] = record;
        }
        var tabs = SyncPayloadType.Tab;
        foreach (var tab in byId.Values.Where(r => r.KindName == tabs.Kind.Name && PayloadValue(r) is not null).ToArray()) {
            string archiveName = tabs.Counterpart!.Kind.RecordName(tab.Id);
            if (!byId.TryGetValue(archiveName, out var archiveRecord) || PayloadValue(archiveRecord) is not { } archive) continue;
            var payload = PayloadValue(tab)!;
            bool active = Placement(payload).KeepsTabOverArchive(Date(payload, StoredSessionCodec.Key.LastActivatedAt)!.Value,
                tab.Version, ArchiveReason.Named(Text(archive, StoredSessionCodec.Key.Reason)) ?? ArchiveReason.Closed,
                Date(archive, StoredSessionCodec.Key.ArchivedAt)!.Value, archiveRecord.Version);
            byId.Remove(active ? archiveName : tab.Name);
        }
        return new JsonArray(byId.OrderBy(p => p.Key, StringComparer.Ordinal).Select(p => p.Value.Json.DeepClone()).ToArray());
    }

    #endregion
}
