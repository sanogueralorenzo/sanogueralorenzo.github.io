using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// A payload's members read exactly as the Apple clients' decoder reads them:
/// a required member must be present and of its type, an optional one may be
/// absent or null but is otherwise of its type, and a tolerant one takes its
/// default for anything it cannot read. Every failure throws
/// `UnreadableSyncPayloadException`.
internal sealed class SyncPayloadReader {
    #region Variables

    /// The object read.
    public JsonObject Value { get; }

    /// How the payload spells its dates.
    public SyncPayloadForm Form { get; }

    #endregion

    #region Constructors

    public SyncPayloadReader(JsonNode? value, SyncPayloadForm form) {
        Value = value as JsonObject ?? throw new UnreadableSyncPayloadException();
        Form = form;
    }

    #endregion

    #region Actions - Members

    /// The object `key` holds, read in this form.
    public SyncPayloadReader Nested(string key) => new(Value[key], Form);

    /// The object `key` holds, or null when it holds none.
    public SyncPayloadReader? OptionalNested(string key) => Value[key] is null ? null : Nested(key);

    /// The array `key` holds.
    public JsonArray Array(string key) => Value[key] as JsonArray ?? throw new UnreadableSyncPayloadException();

    /// The array `key` holds, or null when it holds none.
    public JsonArray? OptionalArray(string key) => Value[key] is null ? null : Array(key);

    public string Text(string key) => Text(Value[key]);

    public string? OptionalText(string key) => Value[key] is null ? null : Text(key);

    /// The text `key` holds, or null for anything that is not text.
    public string? TolerantText(string key) => Value[key] is JsonValue value && value.GetValueKind() == JsonValueKind.String
        ? value.GetValue<string>() : null;

    public bool Flag(string key) => Flag(Value[key]);

    public bool? OptionalFlag(string key) => Value[key] is null ? null : Flag(key);

    /// The flag `key` holds, or null for anything that is not a flag.
    public bool? TolerantFlag(string key) => Value[key] is JsonValue value && value.GetValueKind() is JsonValueKind.True or JsonValueKind.False
        ? value.GetValue<bool>() : null;

    public double Number(string key) => Number(Value[key]);

    public double? OptionalNumber(string key) => Value[key] is null ? null : Number(key);

    /// The number `key` holds, or null for anything that is not a number.
    public double? TolerantNumber(string key) {
        try {
            return OptionalNumber(key);
        } catch (UnreadableSyncPayloadException) {
            return null;
        }
    }

    public long Integer(string key) => Integer(Value[key]);

    public long? OptionalInteger(string key) => Value[key] is null ? null : Integer(key);

    /// The integer `key` holds, or null for anything that is not one.
    public long? TolerantInteger(string key) {
        try {
            return OptionalInteger(key);
        } catch (UnreadableSyncPayloadException) {
            return null;
        }
    }

    /// The identity `key` holds as bare text.
    public Guid Identity(string key) => Identity(Value[key]);

    public Guid? OptionalIdentity(string key) => Value[key] is null ? null : Identity(key);

    /// The identity `key` holds as `{"rawValue": identity}`.
    public Guid WrappedIdentity(string key) => Nested(key).Identity(StoredSessionCodec.Key.RawValue);

    public Guid? OptionalWrappedIdentity(string key) => Value[key] is null ? null : WrappedIdentity(key);

    public SyncTime Time(string key) => Form.Time(Number(key));

    public SyncTime? OptionalTime(string key) => Value[key] is null ? null : Time(key);

    /// The member of a closed set `key` names, which must be one `named` knows.
    public T Named<T>(string key, Func<string?, T?> named) where T : class => named(Text(key)) ?? throw new UnreadableSyncPayloadException();

    /// As `Named`, or null when `key` holds nothing.
    public T? OptionalNamed<T>(string key, Func<string?, T?> named) where T : class => Value[key] is null ? null : Named(key, named);

    #endregion

    #region Actions - Values

    public static string Text(JsonNode? node) => node is JsonValue value && value.GetValueKind() == JsonValueKind.String
        ? value.GetValue<string>() : throw new UnreadableSyncPayloadException();

    public static bool Flag(JsonNode? node) => node is JsonValue value && value.GetValueKind() is JsonValueKind.True or JsonValueKind.False
        ? value.GetValue<bool>() : throw new UnreadableSyncPayloadException();

    /// A finite number, as a double, whether parsed or placed in a node by code.
    public static double Number(JsonNode? node) =>
        SyncJson.TryDouble(node, out var number) && double.IsFinite(number) ? number : throw new UnreadableSyncPayloadException();

    /// A number that is a whole 64-bit integer, however it is spelled.
    public static long Integer(JsonNode? node) {
        if (SyncJson.TryLong(node, out var whole)) return whole;
        if (node is JsonValue value && value.TryGetValue(out decimal exact) && exact == decimal.Truncate(exact)
            && exact is >= long.MinValue and <= long.MaxValue)
            return (long)exact;
        if (SyncJson.TryDouble(node, out var number) && number == Math.Floor(number) && number is >= long.MinValue and < long.MaxValue)
            return (long)number;
        throw new UnreadableSyncPayloadException();
    }

    /// An identity in its hyphenated spelling, in either letter case.
    public static Guid Identity(JsonNode? node) =>
        Guid.TryParseExact(Text(node), "D", out var id) ? id : throw new UnreadableSyncPayloadException();

    #endregion
}
