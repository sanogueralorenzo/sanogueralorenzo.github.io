using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// What a live synced record carries: the value of one Space, folder, tab,
/// visit or archived tab, read with the defaults every Apple client reads it
/// with and written in either form. The value's kind spells itself as `type`
/// beside it.
internal abstract record SyncPayload {
    #region Static Variables

    /// The widest a fractional position is spelled, in hex digits.
    private const int MaximumOrderTokenLength = 16;

    #endregion

    #region Variables

    /// The kind of record the payload is.
    public abstract SyncRecordKind Kind { get; }

    /// The identity of the record the payload is.
    public abstract Guid Id { get; }

    /// The Space the payload belongs to.
    public abstract Guid SpaceId { get; }

    /// The oldest CloudKit schema whose clients read the payload whole: 1
    /// unless it carries something older clients cannot place.
    public virtual int Schema => 1;

    #endregion

    #region Abstract Methods

    /// Throws `UnreadableSyncPayloadException` when the payload breaks a rule
    /// every client checks before it takes a record.
    public abstract void Validate();

    /// The payload's value as `form` spells it, without the members this build
    /// does not know.
    public abstract JsonObject EncodeValue(SyncPayloadForm form);

    #endregion

    #region Actions - Sending

    /// Throws `UnreadableSyncPayloadException` when this device should not send
    /// the payload, which every client would read: an address it cannot spell
    /// as every client parses it.
    public virtual void RequireSendable() {
    }

    #endregion

    #region Actions - Coding

    /// The payload `envelope` holds as `form` spells it: `{"type", "value"}`.
    /// Throws `UnreadableSyncPayloadException` for one no client reads.
    public static SyncPayload Decode(JsonNode? envelope, SyncPayloadForm form) {
        var reader = new SyncPayloadReader(envelope, form);
        return reader.Named("type", SyncPayloadType.Named).Read(reader.Nested("value"));
    }

    /// The payload as `form` spells it, without the members this build does
    /// not know.
    public JsonObject Encode(SyncPayloadForm form) => new() { ["type"] = Kind.Name, ["value"] = EncodeValue(form) };

    #endregion

    #region Actions - Validation

    /// Text a client reads in a field: not empty, and at most `limit` bytes of UTF-8.
    protected static void RequireText(string text, int limit) {
        if (text.Length == 0 || Encoding.UTF8.GetByteCount(text) > limit) throw new UnreadableSyncPayloadException();
    }

    /// A fractional position every client reads: hex digits, at most sixteen.
    protected static void RequireOrderToken(string token) {
        if (token.Length is 0 or > MaximumOrderTokenLength || !token.All(char.IsAsciiHexDigit)) throw new UnreadableSyncPayloadException();
    }

    /// An address a client reads in a web field; see `SyncedAddress`.
    protected static void RequireWebAddress(SyncedAddress address) {
        if (!address.IsReadableWebAddress) throw new UnreadableSyncPayloadException();
    }

    /// An address this device sends in a web field; see `SyncedAddress`.
    protected static void RequireSendableAddress(SyncedAddress address) {
        if (!address.IsSendable) throw new UnreadableSyncPayloadException();
    }

    #endregion

    #region Actions - Writing

    /// Writes `time` into `value` under `key` as `form` spells it, when there is one.
    protected static void Put(JsonObject value, string key, SyncTime? time, SyncPayloadForm form) {
        if (time is { } moment) value[key] = form.Seconds(moment);
    }

    protected static void Put(JsonObject value, string key, string? text) {
        if (text is not null) value[key] = text;
    }

    /// Writes `id` into `value` under `key` as `{"rawValue": id}`, when there is one.
    protected static void PutWrapped(JsonObject value, string key, Guid? id) {
        if (id is { } identity) value[key] = StoredSessionCodec.WrappedIdentity(identity);
    }

    #endregion
}
