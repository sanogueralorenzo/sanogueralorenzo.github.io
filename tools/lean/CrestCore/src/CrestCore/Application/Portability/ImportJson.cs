using System.Globalization;
using System.Text.Json;

namespace CrestCore.Application;

/// Values of another browser's JSON, read as loosely as the Apple platforms'
/// JSON reader hands them to a reader: a member of the wrong type reads as
/// missing, and a number and a boolean are both numbers.
internal static class ImportJson {
    #region Static Variables

    /// How deep another browser's JSON may nest.
    private static readonly JsonDocumentOptions Document = new() { MaxDepth = 512 };

    #endregion

    #region Actions - Documents

    /// The document `contents` holds, or null when it is not JSON.
    public static JsonDocument? Parse(ReadOnlyMemory<byte> contents) {
        try {
            return JsonDocument.Parse(contents, Document);
        } catch (JsonException) {
            return null;
        }
    }

    #endregion

    #region Actions - Members

    /// The member `key` of `value`, when `value` is an object that holds it.
    public static JsonElement? Member(JsonElement? value, string key) =>
        value is { ValueKind: JsonValueKind.Object } found && found.TryGetProperty(key, out var member) ? member : null;

    public static JsonElement? Object(JsonElement? value) => value is { ValueKind: JsonValueKind.Object } ? value : null;

    public static IReadOnlyList<JsonElement>? Array(JsonElement? value) =>
        value is { ValueKind: JsonValueKind.Array } found ? [.. found.EnumerateArray()] : null;

    public static string? Text(JsonElement? value) => value is { ValueKind: JsonValueKind.String } found ? found.GetString() : null;

    /// A number, with true as one and false as zero.
    public static double? Number(JsonElement? value) => value switch {
        { ValueKind: JsonValueKind.Number } found => found.TryGetDouble(out double number) ? number : null,
        { ValueKind: JsonValueKind.True } => 1,
        { ValueKind: JsonValueKind.False } => 0,
        _ => null
    };

    /// A number truncated toward zero.
    public static long? Integer(JsonElement? value) => Number(value) is { } number && double.IsFinite(number)
        ? (long)Math.Clamp(Math.Truncate(number), long.MinValue, long.MaxValue) : null;

    /// A number read as a flag: anything but zero is true.
    public static bool? Flag(JsonElement? value) => Number(value) is { } number ? number != 0 : null;

    /// The members of an object, in the order the document spells them.
    public static IEnumerable<JsonProperty> Members(JsonElement? value) =>
        value is { ValueKind: JsonValueKind.Object } found ? found.EnumerateObject() : [];

    /// A number spelled in a string, as another browser keeps some times.
    public static double? SpelledNumber(string text) =>
        double.TryParse(text, NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint | NumberStyles.AllowExponent,
            CultureInfo.InvariantCulture, out double number) ? number : null;

    #endregion
}
