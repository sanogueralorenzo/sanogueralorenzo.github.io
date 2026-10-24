using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// What a deleted record carries: why it was deleted and when.
internal sealed record SyncTombstone(SyncDeletionReason Reason, SyncTime DeletedAt) {
    #region Actions - Coding

    /// The tombstone `value` holds as `form` spells it. Throws
    /// `UnreadableSyncPayloadException` for one no client reads.
    public static SyncTombstone Decode(JsonNode? value, SyncPayloadForm form) {
        var reader = new SyncPayloadReader(value, form);
        return new(reader.Named("reason", SyncDeletionReason.Named), reader.Time("deletedAt"));
    }

    public JsonObject Encode(SyncPayloadForm form) => new() { ["reason"] = Reason.Name, ["deletedAt"] = form.Seconds(DeletedAt) };

    #endregion
}
