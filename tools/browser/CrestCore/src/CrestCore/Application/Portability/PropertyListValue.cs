namespace CrestCore.Application;

/// Values of a property list, read as loosely as the Apple platforms hand
/// them to a reader: a value of the wrong type reads as missing, and numbers
/// and flags are both numbers.
internal static class PropertyListValue {
    #region Actions - Values

    public static IReadOnlyDictionary<string, object>? Dictionary(object? value) => value as IReadOnlyDictionary<string, object>;

    public static IReadOnlyList<object>? Array(object? value) => value as IReadOnlyList<object>;

    public static string? Text(object? value) => value as string;

    public static object? Member(IReadOnlyDictionary<string, object>? dictionary, string key) =>
        dictionary is not null && dictionary.TryGetValue(key, out var value) ? value : null;

    /// A number, with true as one and false as zero.
    public static double? Number(object? value) => value switch {
        long whole => whole,
        double real => real,
        bool flag => flag ? 1 : 0,
        _ => null
    };

    /// A number truncated toward zero.
    public static long? Integer(object? value) => value switch {
        long whole => whole,
        double real when double.IsFinite(real) => (long)Math.Clamp(Math.Truncate(real), long.MinValue, long.MaxValue),
        bool flag => flag ? 1 : 0,
        _ => null
    };

    /// A number read as a flag: anything but zero is true.
    public static bool? Flag(object? value) => Number(value) is { } number ? number != 0 : null;

    /// The first of `keys` whose value is an array.
    public static IReadOnlyList<object>? FirstArray(IReadOnlyDictionary<string, object>? dictionary, IEnumerable<string> keys) =>
        keys.Select(key => Array(Member(dictionary, key))).FirstOrDefault(value => value is not null);

    /// The first of `keys` whose value is text.
    public static string? FirstText(IReadOnlyDictionary<string, object>? dictionary, IEnumerable<string> keys) =>
        keys.Select(key => Text(Member(dictionary, key))).FirstOrDefault(value => value is not null);

    /// The first of `keys` whose value is a number, truncated.
    public static long? FirstInteger(IReadOnlyDictionary<string, object>? dictionary, IEnumerable<string> keys) =>
        keys.Select(key => Integer(Member(dictionary, key))).FirstOrDefault(value => value is not null);

    /// The first of `keys` whose value is a number, as a flag.
    public static bool? FirstFlag(IReadOnlyDictionary<string, object>? dictionary, IEnumerable<string> keys) =>
        keys.Select(key => Flag(Member(dictionary, key))).FirstOrDefault(value => value is not null);

    #endregion
}
