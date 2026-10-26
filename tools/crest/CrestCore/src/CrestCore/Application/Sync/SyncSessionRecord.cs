using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// A journal record read once for convergence. The journal keeps its opaque
/// additions; session behavior uses its payload, ownership and deletion cause.
internal sealed record SyncSessionRecord(SyncRecordKind Kind, Guid Id, Guid SpaceId, SyncPayload? Payload, SyncTombstone? Tombstone,
    bool SuppliesBranding, bool SuppliesFolderColor) {
    #region Actions - Coding

    public static SyncSessionRecord Read(JsonObject json) {
        var record = new SyncJournalRecord(json);
        var payload = record.Payload;
        var value = payload?[SyncPayload.Key.Value];
        return new(SyncRecordKind.Named(record.KindName)!, record.Id, record.SpaceId,
            payload is null ? null : ReadPayload(payload),
            record.Tombstone is { } tombstone ? SyncTombstone.Decode(tombstone, SyncPayloadForm.Journal) : null,
            value?[StoredSessionCodec.Key.Branding] is not null, value?[StoredSessionCodec.Key.Color] is not null);
    }

    /// Stored journals predate the cloud's strict readers. Supply the same
    /// checkpoint defaults their session materializer used, without changing
    /// the journal or the cloud reader's validation.
    private static SyncPayload ReadPayload(JsonNode payload) {
        var type = SyncPayloadType.Of(payload);
        var value = SyncPayload.ValueOf(payload);
        var prepared = value.DeepClone().AsObject();
        if (type == SyncPayloadType.Tab) prepared = ReadTab(value);
        else if (type == SyncPayloadType.Folder) {
            prepared = Placed(StoredSessionCodec.Encode(StoredSessionCodec.DecodeFolder(value)), value);
        } else if (type == SyncPayloadType.Archive) {
            prepared[StoredSessionCodec.Key.Tab] = ReadTab(value[StoredSessionCodec.Key.Tab]!.AsObject());
            prepared[StoredSessionCodec.Key.Reason] =
                ArchiveReason.Named(value[StoredSessionCodec.Key.Reason]?.GetValue<string>())?.Name ?? ArchiveReason.Closed.Name;
        }
        return type.Read(new SyncPayloadReader(prepared, SyncPayloadForm.Journal));
    }

    private static JsonObject ReadTab(JsonObject value) => Placed(StoredSessionCodec.Encode(StoredSessionCodec.DecodeTab(value)), value);

    /// `prepared` with the Space and position `value` names, which the stored
    /// folder and tab codecs leave out; an empty position when it names none.
    private static JsonObject Placed(JsonObject prepared, JsonObject value) {
        prepared[StoredSessionCodec.Key.SpaceId] = value[StoredSessionCodec.Key.SpaceId]!.DeepClone();
        prepared[SyncPayload.Key.OrderToken] = value[SyncPayload.Key.OrderToken]?.DeepClone() ?? JsonValue.Create("");
        return prepared;
    }

    #endregion
}
