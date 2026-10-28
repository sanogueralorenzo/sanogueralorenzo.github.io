using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

/// Reads identities and numbers at the sync JSON boundary. Numbers read the same way however a
/// node was built. A number parsed from text reads as any numeric type that
/// holds it, while one built in code reads only as the type it was built
/// with, so a typed `GetValue` would read a record the codec built differently
/// from the same record parsed from the journal.
internal static class SyncJson {
    #region Actions - Reading

    /// A nonempty sync identity, accepting the legacy wrapped spelling as well
    /// as a bare UUID. Session repair has its own more tolerant stored decoder.
    public static Guid Identity(JsonNode? value) {
        if (value is JsonObject obj) value = obj[StoredSessionCodec.Key.RawValue];
        var id = Guid.Parse(value!.GetValue<string>());
        if (id == Guid.Empty) throw new BrowserRuleException(BrowserRule.InvalidIdentity);
        return id;
    }

    /// `node` as a double. Throws `InvalidOperationException` when it holds no
    /// number.
    public static double Double(JsonNode node) =>
        TryDouble(node, out var number) ? number : throw new InvalidOperationException("The value is not a number.");

    /// `node` as a double, or false when it holds no number.
    public static bool TryDouble(JsonNode? node, out double number) {
        number = 0;
        if (node is not JsonValue value || value.GetValueKind() != JsonValueKind.Number) return false;
        if (value.TryGetValue(out double real)) number = real;
        else if (value.TryGetValue(out float single)) number = single;
        else if (value.TryGetValue(out decimal exact)) number = (double)exact;
        else if (TryWhole(value, out var whole)) number = (double)whole;
        else return false;
        return true;
    }

    /// `node` as an `int`. Throws `InvalidOperationException` when it holds no
    /// whole number in range.
    public static int Int(JsonNode node) =>
        TryInt(node, out var number) ? number : throw new InvalidOperationException("The value is not a whole number in range.");

    /// `node` as an `int`, or false when it holds no whole number in range.
    public static bool TryInt(JsonNode? node, out int number) {
        number = 0;
        if (node is not JsonValue value || !TryWhole(value, out var whole) || whole < int.MinValue || whole > int.MaxValue) return false;
        number = (int)whole;
        return true;
    }

    /// `node` as a `long`, or false when it holds no whole number in range.
    public static bool TryLong(JsonNode? node, out long number) {
        number = 0;
        if (node is not JsonValue value || !TryWhole(value, out var whole) || whole < long.MinValue || whole > long.MaxValue) return false;
        number = (long)whole;
        return true;
    }

    /// `node` as a `ulong`. Throws `InvalidOperationException` when it holds no
    /// whole number in range.
    public static ulong ULong(JsonNode node) =>
        node is JsonValue value && TryWhole(value, out var whole) && whole >= 0 && whole <= ulong.MaxValue
            ? (ulong)whole : throw new InvalidOperationException("The value is not a whole number in range.");

    /// The whole number `value` holds exactly, whichever integer type it was
    /// built with. A number spelled with a fraction or an exponent is not one,
    /// as a parsed number reads.
    private static bool TryWhole(JsonValue value, out Int128 whole) {
        whole = 0;
        if (value.GetValueKind() != JsonValueKind.Number) return false;
        if (value.TryGetValue(out long signed)) whole = signed;
        else if (value.TryGetValue(out ulong unsigned)) whole = unsigned;
        else if (value.TryGetValue(out int small)) whole = small;
        else if (value.TryGetValue(out uint smallUnsigned)) whole = smallUnsigned;
        else if (value.TryGetValue(out short shorter)) whole = shorter;
        else if (value.TryGetValue(out ushort shorterUnsigned)) whole = shorterUnsigned;
        else if (value.TryGetValue(out byte octet)) whole = octet;
        else if (value.TryGetValue(out sbyte signedOctet)) whole = signedOctet;
        else return false;
        return true;
    }

    #endregion
}
