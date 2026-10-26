using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// The device's search catalog as the device store keeps it: one JSON
/// document. A built-in, option, value or added provider this build cannot
/// read is left out as the catalog restores; a document that does not read at
/// all reads as no catalog kept.
internal static class SearchCatalogDocument {
    #region Static Variables

    private const string DefaultKey = "default";
    private const string PrivateKey = "private";
    private const string SuggestionsKey = "suggestions";
    private const string LanguageKey = "language";
    private const string RegionKey = "region";
    private const string BuiltInsKey = "builtIns";
    private const string CustomKey = "custom";
    private const string NameKey = "name";
    private const string EnabledKey = "enabled";
    private const string ShortcutsKey = "shortcuts";
    private const string OptionsKey = "options";
    private const string IdKey = "id";
    private const string KindKey = "kind";
    private const string SearchKey = "search";
    private const string SuggestKey = "suggest";
    private const string ColorKey = "color";
    private const string RedKey = "red";
    private const string GreenKey = "green";
    private const string BlueKey = "blue";

    #endregion

    #region Actions - Reading

    /// The catalog `document` holds, restored, or null when it does not read.
    public static SearchCatalog? Read(string? document) {
        if (document is null) return null;
        try {
            if (JsonNode.Parse(document, documentOptions: new() { MaxDepth = 8 }) is not JsonObject value) return null;
            var builtIns = (value[BuiltInsKey] as JsonArray ?? []).OfType<JsonObject>().Select(BuiltIn).OfType<SearchProviderSettings>();
            var custom = (value[CustomKey] as JsonArray ?? []).OfType<JsonObject>().Select(Custom).OfType<CustomSearchProvider>();
            var (builtIn, customId) = Chosen(Text(value[DefaultKey]));
            var (privateBuiltIn, privateCustomId) = Chosen(Text(value[PrivateKey]));
            return new SearchCatalog([.. builtIns], [.. custom], builtIn, customId, privateBuiltIn, privateCustomId,
                value[SuggestionsKey] is JsonValue flag
                && flag.TryGetValue<bool>(out bool suggests) && suggests, Text(value[LanguageKey]), Text(value[RegionKey])).Restored();
        } catch (JsonException) {
            return null;
        }
    }

    /// The provider a stored default names: a built-in's name, or `custom:`
    /// and an added provider's identity.
    private static (BuiltInSearchProvider? BuiltIn, Guid? CustomId) Chosen(string? name) =>
        name is not null && name.StartsWith(SearchProvider.CustomPrefix, StringComparison.Ordinal)
        && Guid.TryParseExact(name[SearchProvider.CustomPrefix.Length..], "D", out var id)
            ? (null, id) : (BuiltInSearchProvider.Named(name), null);

    private static SearchProviderSettings? BuiltIn(JsonObject value) {
        if (BuiltInSearchProvider.Named(Text(value[NameKey])) is not { } provider) return null;
        var options = (value[OptionsKey] as JsonObject ?? []).Select(entry =>
            SearchProviderOption.Named(entry.Key) is { } option && Text(entry.Value) is { } chosen ? new SearchOptionSetting(option, chosen) : null);
        return new(provider, value[EnabledKey] is JsonValue flag && flag.TryGetValue<bool>(out bool enabled) ? enabled : provider.IsEnabledByDefault,
            value[ShortcutsKey] is JsonArray shortcuts ? [.. shortcuts.Select(Text).OfType<string>()] : null,
            [.. options.OfType<SearchOptionSetting>()]);
    }

    private static CustomSearchProvider? Custom(JsonObject value) {
        if (!Guid.TryParse(Text(value[IdKey]), out var id)) return null;
        var color = value[ColorKey] as JsonObject;
        return new(id, Text(value[NameKey]) ?? "", Text(value[SearchKey]) ?? "", Text(value[SuggestKey]),
            SearchProviderKind.Named(Text(value[KindKey])) ?? SearchProviderKind.Engine,
            [.. (value[ShortcutsKey] as JsonArray ?? []).Select(Text).OfType<string>()],
            color is null ? null : new BrandColor(Number(color[RedKey]), Number(color[GreenKey]), Number(color[BlueKey])));
    }

    #endregion

    #region Actions - Writing

    /// `catalog` as its one document, holding only what differs from how
    /// each built-in ships.
    public static string Write(SearchCatalog catalog) {
        ArgumentNullException.ThrowIfNull(catalog);
        var builtIns = new JsonArray();
        foreach (var settings in catalog.BuiltIns.Where(settings => settings != SearchProviderSettings.Starting(settings.Provider))) {
            var value = new JsonObject { [NameKey] = settings.Provider.Name, [EnabledKey] = settings.IsEnabled };
            if (settings.Shortcuts is { } shortcuts) value[ShortcutsKey] = Strings(shortcuts);
            if (settings.Options.Count > 0)
                value[OptionsKey] = new JsonObject(settings.Options.Select(setting =>
                    KeyValuePair.Create(setting.Option.Name, (JsonNode?)JsonValue.Create(setting.Value))));
            builtIns.Add((JsonNode)value);
        }
        return new JsonObject {
            [DefaultKey] = catalog.Default.Name,
            [PrivateKey] = catalog.PrivateDefault.Name,
            [SuggestionsKey] = catalog.SuggestionsEnabled,
            [LanguageKey] = catalog.Language,
            [RegionKey] = catalog.Region,
            [BuiltInsKey] = builtIns,
            [CustomKey] = new JsonArray([.. catalog.Custom.Select(provider => {
                var value = new JsonObject {
                    [IdKey] = provider.Id.ToString("D", CultureInfo.InvariantCulture),
                    [NameKey] = provider.Name,
                    [KindKey] = provider.Kind.Name,
                    [ShortcutsKey] = Strings(provider.Shortcuts),
                    [SearchKey] = provider.SearchUrlTemplate,
                    [SuggestKey] = provider.SuggestionUrlTemplate
                };
                if (provider.Color is { } color)
                    value[ColorKey] = new JsonObject { [RedKey] = color.Red, [GreenKey] = color.Green, [BlueKey] = color.Blue };
                return (JsonNode)value;
            })])
        }.ToJsonString();
    }

    #endregion

    #region Actions - Support

    private static JsonArray Strings(IEnumerable<string> values) => new([.. values.Select(value => (JsonNode)JsonValue.Create(value)!)]);

    private static string? Text(JsonNode? node) => node is JsonValue value && value.TryGetValue<string>(out var text) ? text : null;

    private static double Number(JsonNode? node) =>
        node is JsonValue value && value.TryGetValue<double>(out var number) && double.IsFinite(number) ? Math.Clamp(number, 0, 1) : 0.5;

    #endregion
}
