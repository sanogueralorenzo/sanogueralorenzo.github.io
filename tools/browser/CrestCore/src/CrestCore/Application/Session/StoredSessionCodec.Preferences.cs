using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

internal static partial class StoredSessionCodec {
    #region Variables

    /// What a Space that stored no browsing preferences searches and keeps.
    internal static BrowsingPreferences DefaultBrowsingPreferences { get; } = new(BuiltInSearchProvider.Google, null, [], false,
        FollowsDefaultSearch: true, FollowsDefaultSuggestions: true, CurrentTabCleanup.After12Hours, ContentBlockingPolicy.Balanced,
        new(DataRetention.Forever, DataRetention.Forever, DataRetention.Forever));

    /// What a Space that stored no credential preferences offers.
    internal static CredentialPreferences DefaultCredentialPreferences { get; } = new(true, true, false);

    #endregion

    #region Actions - Browsing preferences

    /// A Space's browsing preferences. The selection falls back to the legacy
    /// provider member, a custom engine without a readable identity is left out,
    /// a Space an older release stored searches and suggests as it chose rather
    /// than following the default, a missing cleanup policy is twelve hours and
    /// an unknown one never cleans.
    internal static BrowsingPreferences DecodeBrowsingPreferences(JsonNode? node) {
        var value = Object(node);
        var retention = value[Key.DataRetention] as JsonObject;
        DataRetention Kept(string key) => DataRetention.Named(TolerantText(retention?[key])) ?? DataRetention.Forever;
        var cleanup = value[Key.CurrentTabCleanupPolicy] is { } stored
            ? CurrentTabCleanup.Named(TolerantText(stored)) ?? CurrentTabCleanup.Never : CurrentTabCleanup.After12Hours;
        var (builtIn, custom) = SearchSelection(TolerantText(value[Key.SelectedSearchProviderId])
            ?? TolerantText(value[Key.LegacySearchProvider]));
        return new(builtIn, custom,
            [.. Items(value[Key.CustomSearchProviders]).OfType<JsonObject>().Select(CustomSearchProvider).OfType<CustomSearchProvider>()],
            TolerantFlag(value[Key.SearchSuggestionsEnabled]) ?? false, TolerantFlag(value[Key.SearchFollowsDefault]) ?? false,
            TolerantFlag(value[Key.SuggestionsFollowDefault]) ?? false, cleanup,
            ContentBlockingPolicy.Named(TolerantText(value[Key.ContentBlockingPolicy])) ?? ContentBlockingPolicy.Balanced,
            new(Kept(Key.History), Kept(Key.Archive), Kept(Key.Downloads)));
    }

    /// The engine a stored selection names: a built-in's spelling, or `custom:`
    /// and a custom engine's identity. One this build cannot read selects Google.
    internal static (BuiltInSearchProvider? BuiltIn, Guid? Custom) SearchSelection(string? spelling) =>
        spelling is not null && spelling.StartsWith(SearchProvider.CustomPrefix, StringComparison.Ordinal)
            && Guid.TryParseExact(spelling[SearchProvider.CustomPrefix.Length..], "D", out var custom)
            ? (null, custom) : (BuiltInSearchProvider.Named(spelling) ?? BuiltInSearchProvider.Google, null);

    /// A selection in its stored spelling.
    internal static string SearchSelection(BrowsingPreferences preferences) =>
        preferences.SelectedCustomEngineId is { } custom ? SearchProvider.CustomName(custom)
            : (preferences.SelectedBuiltInEngine ?? BuiltInSearchProvider.Google).Name;

    /// Older builds read only the legacy provider member, so a custom selection
    /// keeps Google there as their safe fallback. Following the default is
    /// written only where a Space follows it.
    internal static JsonObject Encode(BrowsingPreferences preferences) {
        var encoded = EncodeSelection(preferences);
        if (preferences.FollowsDefaultSearch) encoded[Key.SearchFollowsDefault] = true;
        if (preferences.FollowsDefaultSuggestions) encoded[Key.SuggestionsFollowDefault] = true;
        return encoded;
    }

    private static JsonObject EncodeSelection(BrowsingPreferences preferences) => new() {
        [Key.LegacySearchProvider] = preferences.SelectedCustomEngineId is null
            ? (preferences.SelectedBuiltInEngine ?? BuiltInSearchProvider.Google).Name : BuiltInSearchProvider.Google.Name,
        [Key.SelectedSearchProviderId] = SearchSelection(preferences),
        [Key.CustomSearchProviders] = new JsonArray(preferences.CustomSearchProviders.Select(provider => {
            var value = new JsonObject {
                [Key.Id] = BareIdentity(provider.Id),
                [Key.Name] = provider.Name,
                [Key.SearchUrlTemplate] = provider.SearchUrlTemplate
            };
            Put(value, Key.SuggestionUrlTemplate, provider.SuggestionUrlTemplate);
            return (JsonNode?)value;
        }).ToArray()),
        [Key.SearchSuggestionsEnabled] = preferences.SearchSuggestionsEnabled,
        [Key.CurrentTabCleanupPolicy] = preferences.CurrentTabCleanup.Name,
        [Key.ContentBlockingPolicy] = preferences.ContentBlocking.Name,
        [Key.DataRetention] = new JsonObject {
            [Key.History] = preferences.DataRetention.History.Name,
            [Key.Archive] = preferences.DataRetention.Archive.Name,
            [Key.Downloads] = preferences.DataRetention.Downloads.Name
        }
    };

    private static CustomSearchProvider? CustomSearchProvider(JsonObject value) =>
        Guid.TryParse(TolerantText(value[Key.Id]), out var id)
            ? Contracts.CustomSearchProvider.Carried(id, TolerantText(value[Key.Name]) ?? "", TolerantText(value[Key.SearchUrlTemplate]) ?? "",
                TolerantText(value[Key.SuggestionUrlTemplate]))
            : null;

    #endregion

    #region Actions - Credential preferences

    internal static CredentialPreferences DecodeCredentialPreferences(JsonNode? node) {
        var value = Object(node);
        return new(Flag(value[Key.IsEnabled]) ?? DefaultCredentialPreferences.IsEnabled,
            Flag(value[Key.SyncsCrestPasswordsWithICloud]) ?? DefaultCredentialPreferences.SyncsCrestPasswordsWithICloud,
            Flag(value[Key.AlsoOffersSaveToSystemPasswords]) ?? DefaultCredentialPreferences.AlsoOffersSaveToSystemPasswords);
    }

    internal static JsonObject Encode(CredentialPreferences preferences) => new() {
        [Key.IsEnabled] = preferences.IsEnabled,
        [Key.SyncsCrestPasswordsWithICloud] = preferences.SyncsCrestPasswordsWithICloud,
        [Key.AlsoOffersSaveToSystemPasswords] = preferences.AlsoOffersSaveToSystemPasswords
    };

    #endregion

    #region Actions - App preferences

    /// The app-wide preferences. A value this build cannot read keeps its default,
    /// and translation rules that no longer validate read as none, which never
    /// translates.
    internal static AppPreferences DecodeAppPreferences(JsonNode? node) {
        var value = Object(node);
        var defaults = AppPreferences.Default;
        return new(StartupBehavior.Named(TolerantText(value[Key.StartupBehavior])) ?? defaults.Startup,
            TolerantFlag(value[Key.OffersTranslation]) ?? defaults.OffersTranslation,
            TolerantFlag(value[Key.AutomaticallyTranslates]) ?? defaults.AutomaticallyTranslates,
            TranslationRules(value[Key.TranslationRules]),
            TolerantFlag(value[Key.ChecksSpelling]) ?? defaults.ChecksSpelling,
            TolerantFlag(value[Key.AutomaticallyEntersPictureInPicture]) ?? defaults.AutomaticallyEntersPictureInPicture,
            SavedTabClosePolicy.Named(TolerantText(value[Key.SavedTabClosePolicy])) ?? defaults.SavedTabClose,
            TolerantFlag(value[Key.SavedTabFaviconReturnsToSavedUrl]) ?? defaults.SavedTabFaviconReturnsToSavedUrl,
            TolerantFlag(value[Key.SplitFocusFollowsMouse]) ?? defaults.SplitFocusFollowsMouse,
            TolerantFlag(value[Key.AutomaticallyShowsDeveloperToolbar]) ?? defaults.AutomaticallyShowsDeveloperToolbar,
            DecodePalettePreferences(value[Key.Palette]));
    }

    /// The app-wide preferences. The palette's are written only once they
    /// differ from the defaults, so a release that never stored them reads
    /// its own document back unchanged.
    internal static JsonObject Encode(AppPreferences preferences) {
        var value = new JsonObject {
            [Key.StartupBehavior] = preferences.Startup.Name,
            [Key.OffersTranslation] = preferences.OffersTranslation,
            [Key.AutomaticallyTranslates] = preferences.AutomaticallyTranslates,
            [Key.TranslationRules] = EncodeTranslationRules(preferences.TranslationRules),
            [Key.ChecksSpelling] = preferences.ChecksSpelling,
            [Key.AutomaticallyEntersPictureInPicture] = preferences.AutomaticallyEntersPictureInPicture,
            [Key.SavedTabClosePolicy] = preferences.SavedTabClose.Name,
            [Key.SavedTabFaviconReturnsToSavedUrl] = preferences.SavedTabFaviconReturnsToSavedUrl,
            [Key.SplitFocusFollowsMouse] = preferences.SplitFocusFollowsMouse,
            [Key.AutomaticallyShowsDeveloperToolbar] = preferences.AutomaticallyShowsDeveloperToolbar
        };
        if (!preferences.Palette.Equals(PalettePreferences.Default)) value[Key.Palette] = Encode(preferences.Palette);
        return value;
    }

    /// The palette preferences. A value this build cannot read keeps its
    /// default, a kind of result it cannot name is left out, and a number of
    /// rows it cannot read is the kind's own.
    internal static PalettePreferences DecodePalettePreferences(JsonNode? node) {
        var value = node as JsonObject ?? [];
        var defaults = PalettePreferences.Default;
        List<PaletteSourceChoice> sources = [];
        foreach (var item in (value[Key.Sources] as JsonArray ?? []).OfType<JsonObject>())
            if (PaletteSource.Named(TolerantText(item[Key.Source])) is { } source)
                sources.Add(new(source, TolerantFlag(item[Key.IsEnabled]) ?? source.IsEnabledByDefault,
                    item[Key.Limit] is JsonValue limit && limit.TryGetValue<int>(out int rows) ? rows : null));
        return new PalettePreferences(PaletteLayout.Named(TolerantText(value[Key.Layout])) ?? defaults.Layout, sources,
            TolerantFlag(value[Key.ShowsTopHit]) ?? defaults.ShowsTopHit, TolerantFlag(value[Key.PrefersOpenTabs]) ?? defaults.PrefersOpenTabs,
            TolerantFlag(value[Key.CompletesInline]) ?? defaults.CompletesInline, TolerantFlag(value[Key.LearnsChoices]) ?? defaults.LearnsChoices,
            TolerantFlag(value[Key.SearchesSitesWithTab]) ?? defaults.SearchesSitesWithTab,
            TolerantFlag(value[Key.ShowsReasons]) ?? defaults.ShowsReasons).Restored();
    }

    private static JsonNode Encode(PaletteSourceChoice choice) {
        var value = new JsonObject { [Key.Source] = choice.Source.Name, [Key.IsEnabled] = choice.IsEnabled };
        if (choice.Limit is { } limit) value[Key.Limit] = limit;
        return value;
    }

    internal static JsonObject Encode(PalettePreferences preferences) => new() {
        [Key.Layout] = preferences.Layout.Name,
        [Key.Sources] = new JsonArray([.. preferences.Sources.Select(Encode)]),
        [Key.ShowsTopHit] = preferences.ShowsTopHit,
        [Key.PrefersOpenTabs] = preferences.PrefersOpenTabs,
        [Key.CompletesInline] = preferences.CompletesInline,
        [Key.LearnsChoices] = preferences.LearnsChoices,
        [Key.SearchesSitesWithTab] = preferences.SearchesSitesWithTab,
        [Key.ShowsReasons] = preferences.ShowsReasons
    };

    /// The values the native settings stored before the core owned them, each
    /// under its stored name and null when never saved. Translation rules arrive
    /// as the raw JSON text the native setting stored. A value this build cannot
    /// read keeps its default rather than failing the whole import.
    /// The preferences an older release's settings stored, read as the stored
    /// record is: each value saved in its stored spelling, anything missing
    /// or unreadable the default.
    internal static AppPreferences ImportAppPreferences(LegacyAppPreferences legacy) {
        ArgumentNullException.ThrowIfNull(legacy);
        var stored = new JsonObject();
        Put(stored, Key.StartupBehavior, legacy.StartupBehavior);
        Put(stored, Key.OffersTranslation, legacy.OffersTranslation);
        Put(stored, Key.AutomaticallyTranslates, legacy.AutomaticallyTranslates);
        stored[Key.TranslationRules] = RawTranslationRules(legacy.TranslationRules);
        Put(stored, Key.ChecksSpelling, legacy.ChecksSpelling);
        Put(stored, Key.AutomaticallyEntersPictureInPicture, legacy.AutomaticallyEntersPictureInPicture);
        Put(stored, Key.SavedTabClosePolicy, legacy.SavedTabClosePolicy);
        Put(stored, Key.SavedTabFaviconReturnsToSavedUrl, legacy.SavedTabFaviconReturnsToSavedUrl);
        Put(stored, Key.SplitFocusFollowsMouse, legacy.SplitFocusFollowsMouse);
        return DecodeAppPreferences(stored);
    }

    private static JsonNode? RawTranslationRules(string? text) {
        if (text is null) return null;
        try {
            return JsonNode.Parse(text, documentOptions: new() { MaxDepth = 8 });
        } catch (JsonException) {
            return null;
        }
    }

    /// Rules in their stored shape, `{"sources":{"es":{"targetID":"en","isEnabled":true}}}`.
    internal static IReadOnlyList<TranslationRule> TranslationRules(JsonNode? value) {
        if (value?[Key.Sources] is not JsonObject sources) return AutomaticTranslationRules.Empty.Rules;
        try {
            return AutomaticTranslationRules.Restore(sources.Select(member => new TranslationRule(member.Key,
                TolerantText(member.Value?[Key.TargetId]) ?? "", TolerantFlag(member.Value?[Key.IsEnabled]) ?? false))).Rules;
        } catch (Rejected) {
            return AutomaticTranslationRules.Empty.Rules;
        }
    }

    private static JsonObject EncodeTranslationRules(IReadOnlyList<TranslationRule> rules) {
        var sources = new JsonObject();
        foreach (var rule in rules)
            sources[rule.SourceLanguage] = new JsonObject { [Key.TargetId] = rule.TargetId, [Key.IsEnabled] = rule.IsEnabled };
        return new() { [Key.Sources] = sources };
    }

    /// A startup or saved-tab close choice in its stored spelling, which settings
    /// commands and the launch plan also use; null when this build cannot name it.
    internal static StartupBehavior? ParseStartupBehavior(JsonNode? node) => StartupBehavior.Named(TolerantText(node));

    internal static SavedTabClosePolicy? ParseSavedTabClosePolicy(JsonNode? node) => SavedTabClosePolicy.Named(TolerantText(node));

    #endregion
}
