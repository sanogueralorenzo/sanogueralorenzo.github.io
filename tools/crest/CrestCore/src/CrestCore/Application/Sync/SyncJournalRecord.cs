using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// A sync record as the journal holds it, in the form the Apple clients
/// write: `{"id": {"kind", "value"}, "spaceID", "version": {"logicalClock",
/// "deviceID"}}` with its `payload` or its `tombstone`, beside whatever a
/// newer build added, which the journal keeps. Every reader and writer of a
/// record's envelope goes through it; the journal keeps the JSON itself.
internal readonly record struct SyncJournalRecord(JsonObject Json) {
    #region Types

    /// The envelope's members, and a tombstone's.
    internal static class Key {
        public const string Id = "id";
        public const string Kind = "kind";
        public const string Value = "value";
        public const string SpaceId = "spaceID";
        public const string Version = "version";
        public const string LogicalClock = "logicalClock";
        public const string DeviceId = "deviceID";
        public const string Payload = "payload";
        public const string Tombstone = "tombstone";
        public const string Reason = "reason";
        public const string DeletedAt = "deletedAt";
    }

    #endregion

    #region Variables

    /// The name of the record's kind, as its identity spells it.
    public string KindName => Json[Key.Id]![Key.Kind]!.GetValue<string>();

    public Guid Id => SyncJson.Identity(Json[Key.Id]![Key.Value]);

    /// The record's name in the journal: its kind and identity.
    public string Name => NameOf(Json[Key.Id]!);

    public Guid SpaceId => SyncJson.Identity(Json[Key.SpaceId]);

    public SyncVersion Version => new(Clock, SyncJson.Identity(Json[Key.Version]![Key.DeviceId]));

    /// The logical clock of the record's version.
    public ulong Clock => SyncJson.ULong(Json[Key.Version]![Key.LogicalClock]!);

    /// The record's payload, `{"type", "value"}`, or null for a tombstone.
    public JsonObject? Payload => Json[Key.Payload] as JsonObject;

    public JsonNode? Tombstone => Json[Key.Tombstone];

    public bool IsTombstone => Tombstone is not null;

    /// What the record carries: its tombstone, or its payload.
    public JsonNode? Body => Tombstone ?? Json[Key.Payload];

    /// The record by its kind and identity. Throws `BrowserRuleException` for
    /// a kind no client knows.
    public SyncRecordReference Reference =>
        new(SyncRecordKind.Named(KindName) ?? throw new BrowserRuleException(BrowserRule.InvalidSyncKind), Id);

    #endregion

    #region Actions - Naming

    /// The name of the record `id`, a record's `{"kind", "value"}` identity, names.
    public static string NameOf(JsonNode id) => id[Key.Kind]!.GetValue<string>() + ":" + SyncJson.Identity(id[Key.Value]).ToString("D");

    /// The identity of the record that holds `payload`, as the Apple clients
    /// spell it.
    public static JsonObject IdentityOf(JsonObject payload) {
        var type = SyncPayloadType.Of(payload);
        return Identity(type.Kind, SyncJson.Identity(type.Subject(SyncPayload.ValueOf(payload))[StoredSessionCodec.Key.Id]));
    }

    private static JsonObject Identity(SyncRecordKind kind, Guid id) =>
        new() { [Key.Kind] = kind.Name, [Key.Value] = StoredSessionCodec.BareIdentity(id) };

    #endregion

    #region Actions - Writing

    /// The record `record` describes, carrying `body` in the journal's form.
    public static JsonObject Written(SyncRecord record, JsonObject body) => new() {
        [Key.Id] = Identity(record.Kind, record.Id),
        [Key.SpaceId] = StoredSessionCodec.WrappedIdentity(record.SpaceId),
        [Key.Version] = VersionOf(record.Version.Clock, StoredSessionCodec.BareIdentity(record.Version.DeviceId)),
        [record.IsTombstone ? Key.Tombstone : Key.Payload] = body
    };

    /// `previous`, or a new record when there is none, carrying `payload` at
    /// `version` in place of anything it carried, and keeping every other
    /// member it holds.
    public static JsonObject Saved(JsonObject? previous, JsonObject payload, JsonObject version) {
        var result = previous?.DeepClone().AsObject() ?? new JsonObject();
        result[Key.Id] = IdentityOf(payload);
        result[Key.SpaceId] = SyncPayloadType.Of(payload).SpaceIdentity(SyncPayload.ValueOf(payload)).DeepClone();
        result[Key.Payload] = payload.DeepClone();
        result[Key.Version] = version;
        result.Remove(Key.Tombstone);
        return result;
    }

    /// The tombstone of `previous` at `version`, deleted for `reason` at
    /// `now` in seconds since 2001.
    public static JsonObject Deleted(JsonObject previous, JsonObject version, SyncDeletionReason reason, double now) => new() {
        [Key.Id] = previous[Key.Id]!.DeepClone(),
        [Key.SpaceId] = previous[Key.SpaceId]!.DeepClone(),
        [Key.Version] = version,
        [Key.Tombstone] = new JsonObject { [Key.Reason] = reason.Name, [Key.DeletedAt] = now }
    };

    /// A version at `clock` from the device `deviceId` names, as the journal
    /// holds its own.
    public static JsonObject VersionOf(ulong clock, JsonNode deviceId) =>
        new() { [Key.LogicalClock] = clock, [Key.DeviceId] = deviceId.DeepClone() };

    #endregion
}
