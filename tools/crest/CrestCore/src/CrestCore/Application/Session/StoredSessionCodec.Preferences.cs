using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

internal static partial class StoredSessionCodec {
    #region Variables

    /// A Space that stored no preferences uses balanced blocking and keeps its records.
    internal static BrowsingPreferences DefaultBrowsingPreferences { get; } = new(ContentBlockingPolicy.Balanced,
        new(DataRetention.Forever, DataRetention.Forever, DataRetention.Forever));

    #endregion

    #region Actions - Browsing preferences

    internal static BrowsingPreferences DecodeBrowsingPreferences(JsonNode? node) {
        var value = Object(node);
        var retention = value[Key.DataRetention] as JsonObject;
        DataRetention Kept(string key) => DataRetention.Named(TolerantText(retention?[key])) ?? DataRetention.Forever;
        return new(ContentBlockingPolicy.Named(TolerantText(value[Key.ContentBlockingPolicy])) ?? ContentBlockingPolicy.Balanced,
            new(Kept(Key.History), Kept(Key.Archive), Kept(Key.Downloads)));
    }

    internal static JsonObject Encode(BrowsingPreferences preferences) => new() {
        [Key.ContentBlockingPolicy] = preferences.ContentBlocking.Name,
        [Key.DataRetention] = new JsonObject {
            [Key.History] = preferences.DataRetention.History.Name,
            [Key.Archive] = preferences.DataRetention.Archive.Name,
            [Key.Downloads] = preferences.DataRetention.Downloads.Name
        }
    };

    #endregion

    #region Actions - App preferences

    /// The app-wide preferences. A value this build cannot read keeps its default.
    internal static AppPreferences DecodeAppPreferences(JsonNode? node) {
        var value = Object(node);
        var defaults = AppPreferences.Default;
        return new(TolerantText(value[Key.TranslationLanguage]) is { Length: > 0 } language ? language : defaults.TranslationLanguage,
            SearchProvider.Named(TolerantText(value[Key.SearchProvider])) ?? defaults.SearchProvider);
    }

    /// The app-wide preferences, stored locally.
    internal static JsonObject Encode(AppPreferences preferences) {
        var value = new JsonObject {
            [Key.TranslationLanguage] = preferences.TranslationLanguage
        };
        if (preferences.SearchProvider != SearchProvider.Google) value[Key.SearchProvider] = preferences.SearchProvider.Name;
        return value;
    }

    #endregion
}
