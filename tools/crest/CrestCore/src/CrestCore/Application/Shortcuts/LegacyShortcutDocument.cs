using System.Globalization;
using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The shortcut document earlier releases saved under
/// `crest.keyboard-shortcuts.v1`, which the device store adopts once: a JSON
/// object from each command's stored name to `{"custom": {"_0": chord}}` or
/// `{"unassigned": {}}`, where a chord is `{"key": {"character": "g"},
/// "modifiers": 3}` or `{"key": {"special": "leftArrow"}, "modifiers": 5}` and
/// the modifiers are the native mask's bits. A command this build does not
/// know keeps its entry.
internal static class LegacyShortcutDocument {
    #region Static Variables

    private const string Custom = "custom";
    private const string Unassigned = "unassigned";
    private const string Payload = "_0";
    private const string Key = "key";
    private const string Character = "character";
    private const string Special = "special";
    private const string Modifiers = "modifiers";

    #endregion

    #region Actions - Adoption

    /// Every entry that still reads, in document order. A document that is not
    /// JSON, or an entry the release that wrote it could not have read back,
    /// contributes nothing rather than failing the whole adoption.
    public static IReadOnlyList<KeyValuePair<string, ShortcutChord?>> Read(byte[]? document) {
        if (document is null || document.Length == 0) return [];
        JsonDocument parsed;
        try {
            parsed = JsonDocument.Parse(document, new() { MaxDepth = 8 });
        } catch (JsonException) {
            return [];
        }
        using (parsed) {
            if (parsed.RootElement.ValueKind != JsonValueKind.Object) return [];
            var entries = new List<KeyValuePair<string, ShortcutChord?>>();
            foreach (var member in parsed.RootElement.EnumerateObject())
                if (Entry(member.Value) is { } entry) entries.Add(new(member.Name, entry.Chord));
            return entries;
        }
    }

    /// The chord an entry names, null for one left unassigned, or nothing for
    /// an entry that does not read.
    private static (ShortcutChord? Chord, bool Read)? Entry(JsonElement value) {
        try {
            if (value.ValueKind != JsonValueKind.Object) return null;
            var members = value.EnumerateObject().ToArray();
            if (members.Length != 1 || members[0].Value.ValueKind != JsonValueKind.Object) return null;
            return members[0].Name switch {
                Unassigned => (null, true),
                Custom => Chord(members[0].Value.GetProperty(Payload)) is { } chord ? (chord, true) : null,
                _ => null
            };
        } catch (Exception error) when (error is InvalidOperationException or KeyNotFoundException or FormatException) {
            return null;
        }
    }

    /// A chord as the release decoded it: a character key when it holds
    /// exactly one character, and otherwise a special key it knows.
    private static ShortcutChord? Chord(JsonElement value) {
        var key = value.GetProperty(Key);
        int modifiers = value.GetProperty(Modifiers).GetInt32();
        if (key.TryGetProperty(Character, out var character) && character.ValueKind == JsonValueKind.String
            && character.GetString() is { Length: > 0 and <= ShortcutChord.MaximumCharacterLength } typed
            && new StringInfo(typed).LengthInTextElements == 1)
            return ShortcutChord.Character(typed, modifiers);
        return ShortcutSpecialKey.Named(key.GetProperty(Special).GetString()) is { } special
            ? ShortcutChord.Special(special.Name, modifiers) : null;
    }

    #endregion
}
