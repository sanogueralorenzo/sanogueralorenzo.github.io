using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// A journal record read once for convergence. The journal keeps its opaque
/// additions; session behavior uses its payload, ownership and deletion cause.
internal sealed record SyncSessionRecord(SyncRecordKind Kind, Guid Id, Guid SpaceId, SyncPayload? Payload, SyncTombstone? Tombstone,
    bool SuppliesBranding, bool SuppliesFolderColor) {
    #region Actions - Coding

    public static SyncSessionRecord Read(JsonObject record) {
        var payload = record["payload"];
        return new(SyncRecordKind.Named(record["id"]!["kind"]!.GetValue<string>())!,
            StoredSessionCodec.Identity(record["id"]!["value"]), StoredSessionCodec.Identity(record["spaceID"]),
            payload is null ? null : ReadPayload(payload),
            record["tombstone"] is { } tombstone ? SyncTombstone.Decode(tombstone, SyncPayloadForm.Journal) : null,
            payload?["value"]?["branding"] is not null, payload?["value"]?["color"] is not null);
    }

    /// Stored journals predate the cloud's strict readers. Supply the same
    /// checkpoint defaults their session materializer used, without changing
    /// the journal or the cloud reader's validation.
    private static SyncPayload ReadPayload(JsonNode payload) {
        var type = SyncPayloadType.Of(payload);
        var value = payload["value"]!.AsObject();
        var prepared = value.DeepClone().AsObject();
        if (type == SyncPayloadType.Tab) prepared = ReadTab(value);
        else if (type == SyncPayloadType.Folder) {
            prepared = StoredSessionCodec.Encode(StoredSessionCodec.DecodeFolder(value));
            prepared["spaceID"] = value["spaceID"]!.DeepClone();
            prepared["orderToken"] = value["orderToken"]?.DeepClone() ?? JsonValue.Create("");
        } else if (type == SyncPayloadType.Archive) {
            prepared["tab"] = ReadTab(value["tab"]!.AsObject());
            prepared["reason"] = ArchiveReason.Named(value["reason"]?.GetValue<string>())?.Name ?? ArchiveReason.Closed.Name;
        }
        return SyncPayload.Decode(new JsonObject { ["type"] = type.Kind.Name, ["value"] = prepared }, SyncPayloadForm.Journal);
    }

    private static JsonObject ReadTab(JsonObject value) {
        var prepared = StoredSessionCodec.Encode(StoredSessionCodec.DecodeTab(value));
        prepared["spaceID"] = value["spaceID"]!.DeepClone();
        prepared["orderToken"] = value["orderToken"]?.DeepClone() ?? JsonValue.Create("");
        return prepared;
    }

    #endregion
}
