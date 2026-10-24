using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// One member of a Crest browser-data file, read as strictly as the Apple
/// platforms' decoder reads it: a required member must be there with the
/// right type, an optional one may be missing or null, and any other value
/// makes the whole file invalid.
internal readonly struct BrowserDataValue(JsonObject value) {
    #region Variables

    public JsonObject Object { get; } = value;

    #endregion

    #region Actions - Reading

    public static BrowserDataValue Of(JsonNode? node) => node is JsonObject value ? new(value) : throw Invalid();

    public BrowserDataValue Nested(string key) => Of(Object[key]);

    public BrowserDataValue? OptionalNested(string key) => IsAbsent(key) ? null : Of(Object[key]);

    public IEnumerable<BrowserDataValue> Items(string key) => Array(Object[key]).Select(Of);

    public IEnumerable<BrowserDataValue>? OptionalItems(string key) => IsAbsent(key) ? null : Items(key);

    public string Text(string key) => TextOf(Object[key]);

    public string? OptionalText(string key) => IsAbsent(key) ? null : Text(key);

    public double Number(string key) => NumberOf(Object[key]);

    public double? OptionalNumber(string key) => IsAbsent(key) ? null : Number(key);

    public int Integer(string key) {
        double number = Number(key);
        return number == Math.Floor(number) && number is >= int.MinValue and <= int.MaxValue ? (int)number : throw Invalid();
    }

    public bool? OptionalFlag(string key) {
        if (IsAbsent(key)) return null;
        return Object[key] is JsonValue flag && flag.GetValueKind() is JsonValueKind.True or JsonValueKind.False
            ? flag.GetValue<bool>() : throw Invalid();
    }

    public Guid Identity(string key) => Guid.TryParseExact(Text(key), "D", out var id) ? id : throw Invalid();

    public Guid? OptionalIdentity(string key) => IsAbsent(key) ? null : Identity(key);

    /// A time kept in milliseconds since 1970.
    public DateTimeOffset Date(string key) => ImportDate.FromUnixMilliseconds(Number(key)) ?? throw Invalid();

    public DateTimeOffset? OptionalDate(string key) => IsAbsent(key) ? null : Date(key);

    /// A color kept as its components, or by the name a palette color had
    /// before colors were stored whole, each component kept within 0 through 1.
    public BrandColor? OptionalColor(string key) {
        if (IsAbsent(key)) return null;
        var node = Object[key];
        if (node is JsonValue name && name.GetValueKind() == JsonValueKind.String
            && Tincture.Named(name.GetValue<string>()) is { } tincture) return tincture.Color;
        var color = Of(node);
        return new(Unit(color.Number("red")), Unit(color.Number("green")), Unit(color.Number("blue")),
            Unit(color.OptionalNumber("alpha") ?? 1));
    }

    private bool IsAbsent(string key) => !Object.TryGetPropertyValue(key, out var node) || node is null;

    #endregion

    #region Actions - Values

    public static string TextOf(JsonNode? node) =>
        node is JsonValue text && text.GetValueKind() == JsonValueKind.String ? text.GetValue<string>() : throw Invalid();

    public static double NumberOf(JsonNode? node) =>
        node is JsonValue number && number.GetValueKind() == JsonValueKind.Number ? number.GetValue<double>() : throw Invalid();

    public static JsonArray Array(JsonNode? node) => node as JsonArray ?? throw Invalid();

    /// The refusal of a file holding anything Crest would not keep.
    public static Rejected Invalid() => new(new ArchiveInvalid());

    private static double Unit(double value) => Math.Clamp(value, 0, 1);

    #endregion
}
