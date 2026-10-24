using System.Collections.Immutable;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Domain;

namespace CrestCore.Application;

/// A Space's palette memory as the device store keeps it: one JSON document
/// with when it began, each place's decay day and last typed time, and each
/// pick. A part it cannot read is left out; a document it cannot read at all
/// reads as no memory.
internal static class PaletteMemoryDocument {
    #region Static Variables

    private const string SinceKey = "since";
    private const string PlacesKey = "places";
    private const string PlaceKey = "place";
    private const string DecayDayKey = "decayDay";
    private const string TypedAtKey = "typedAt";
    private const string ChoicesKey = "choices";
    private const string TextKey = "text";
    private const string KindKey = "kind";
    private const string ValueKey = "value";
    private const string UsesKey = "uses";
    private const string UsedAtKey = "usedAt";

    #endregion

    #region Actions - Reading

    /// The memory `document` holds, or null when it does not read.
    public static PaletteMemory? Read(string? document) {
        if (document is null) return null;
        try {
            if (JsonNode.Parse(document, documentOptions: new() { MaxDepth = 8 }) is not JsonObject value
                || Date(value[SinceKey]) is not { } since) return null;
            var places = ImmutableDictionary.CreateBuilder<string, PlaceUse>(StringComparer.Ordinal);
            foreach (var place in (value[PlacesKey] as JsonArray ?? []).OfType<JsonObject>())
                if (Text(place[PlaceKey]) is { } key && Number(place[DecayDayKey]) is { } decayDay)
                    places[key] = new(decayDay, Date(place[TypedAtKey]));
            var choices = ImmutableList.CreateBuilder<PaletteChoice>();
            foreach (var choice in (value[ChoicesKey] as JsonArray ?? []).OfType<JsonObject>())
                if (Text(choice[TextKey]) is { } text && PaletteDestinationKind.Named(Text(choice[KindKey])) is { } kind
                    && Text(choice[ValueKey]) is { } target && Number(choice[UsesKey]) is { } uses && Date(choice[UsedAtKey]) is { } usedAt)
                    choices.Add(new(text, PaletteDestination.Named(kind, target), uses, usedAt));
            return new(since, places.ToImmutable(), choices.ToImmutable());
        } catch (JsonException) {
            return null;
        } catch (InvalidOperationException) {
            return null;
        }
    }

    #endregion

    #region Actions - Writing

    /// `memory` as its one document.
    public static string Write(PaletteMemory memory) {
        ArgumentNullException.ThrowIfNull(memory);
        var value = new JsonObject {
            [SinceKey] = Spelled(memory.Since),
            [PlacesKey] = new JsonArray([.. memory.Places.OrderBy(place => place.Key, StringComparer.Ordinal).Select(place => (JsonNode)new JsonObject {
                [PlaceKey] = place.Key,
                [DecayDayKey] = place.Value.DecayDay,
                [TypedAtKey] = place.Value.TypedAt is { } typed ? Spelled(typed) : null
            })]),
            [ChoicesKey] = new JsonArray([.. memory.Choices.Select(choice => (JsonNode)new JsonObject {
                [TextKey] = choice.Text,
                [KindKey] = choice.Destination.Kind.Name,
                [ValueKey] = choice.Destination.Value,
                [UsesKey] = choice.Uses,
                [UsedAtKey] = Spelled(choice.LastUsedAt)
            })])
        };
        return value.ToJsonString();
    }

    #endregion

    #region Actions - Support

    private static string Spelled(DateTimeOffset date) => date.ToUniversalTime().ToString("O", CultureInfo.InvariantCulture);

    private static DateTimeOffset? Date(JsonNode? node) =>
        Text(node) is { } text && DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var date)
            ? date : null;

    private static string? Text(JsonNode? node) => node is JsonValue value && value.TryGetValue<string>(out var text) ? text : null;

    private static double? Number(JsonNode? node) =>
        node is JsonValue value && value.TryGetValue<double>(out var number) && double.IsFinite(number) ? number : null;

    #endregion
}
