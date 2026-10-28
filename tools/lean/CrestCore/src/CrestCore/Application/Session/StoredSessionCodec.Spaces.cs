using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

internal static partial class StoredSessionCodec {
    #region Variables

    /// What a Space stored without a name shows.
    private const string FallbackSpaceName = "Space";

    #endregion

    #region Actions - Spaces

    /// A Space with its identity, preferences, and browsing records.
    internal static SpaceState DecodeSpace(JsonNode? node) {
        var value = Object(node);
        return new(Identity(value[Key.Id]), Identity(value[Key.Profile]?[Key.Id]),
            new(Text(value[Key.Name]) ?? FallbackSpaceName,
                value[Key.BrowsingPreferences] is JsonObject browsing ? DecodeBrowsingPreferences(browsing) : DefaultBrowsingPreferences,
                Flag(value[Key.IsGitHubFolderDismissed]) ?? false,
                SpaceColor.Named(Text(value[Key.SpaceColor])) ?? SpaceColor.For(Identity(value[Key.Id]))),
            [.. Items(value[Key.Folders]).Select(DecodeFolder)],
            [.. Items(value[Key.Tabs]).Select(DecodeTab)],
            [.. Items(value[Key.ArchivedTabs]).Select(DecodeArchivedTab)],
            [.. Items(value[Key.History]).Select(DecodeHistoryEntry)]);
    }

    internal static JsonObject Encode(SpaceState space) {
        var settings = space.Settings;
        var value = new JsonObject {
            [Key.Id] = WrappedIdentity(space.Id),
            [Key.Profile] = new JsonObject { [Key.Id] = BareIdentity(space.ProfileId) },
            [Key.Name] = settings.Name
        };
        value[Key.SpaceColor] = settings.Color.Name;
        value[Key.Folders] = EncodeAll(space.Folders, Encode);
        value[Key.Tabs] = EncodeAll(space.Tabs, Encode);
        value[Key.ArchivedTabs] = EncodeAll(space.ArchivedTabs, Encode);
        value[Key.History] = EncodeHistory(space.History);
        value[Key.BrowsingPreferences] = Encode(settings.BrowsingPreferences);
        if (settings.IsGitHubFolderDismissed) value[Key.IsGitHubFolderDismissed] = true;
        return value;
    }

    internal static JsonArray EncodeHistory(IEnumerable<HistoryEntryState> history) => EncodeAll(history, Encode);

    /// A stored access policy. None is open; a policy this build cannot name was
    /// somebody restricting the Space, so it resolves to the guarded side.
    #endregion

    #region Actions - Session

    /// A session; unlike its other members, its Spaces are never optional.
    internal static SessionState DecodeSession(JsonNode? node) {
        var value = Object(node);
        var spaces = value[Key.Spaces] as JsonArray ?? throw new BrowserRuleException(BrowserRule.InvalidSavedState);
        return new([.. spaces.Select(DecodeSpace)],
            OptionalIdentity(value[Key.DisposableSeedMarker]),
            DecodeSpaceDeletions(value[Key.SpaceDeletions]) ?? [],
            value[Key.AppPreferences] is JsonObject preferences ? DecodeAppPreferences(preferences) : null);
    }

    internal static JsonObject Encode(SessionState session) {
        var value = new JsonObject { [Key.Spaces] = EncodeAll(session.Spaces, Encode) };
        if (session.DisposableSeedMarker is { } marker) value[Key.DisposableSeedMarker] = BareIdentity(marker);
        if (session.SpaceDeletions.Count > 0) value[Key.SpaceDeletions] = EncodeAll(session.SpaceDeletions, Encode);
        if (session.AppPreferences is { } preferences) value[Key.AppPreferences] = Encode(preferences);
        return value;
    }

    /// The Space deletions a session stores, or null when it stores none.
    internal static IReadOnlyList<SpaceDeletionState>? DecodeSpaceDeletions(JsonNode? node) => node switch {
        null => null,
        JsonArray intents => [.. intents.Select(intent => intent is JsonObject value
            ? new SpaceDeletionState(Identity(value[Key.OperationId]), Identity(value[Key.SpaceId]), Identity(value[Key.ProfileId]))
            : throw new BrowserRuleException(BrowserRule.InvalidDeletionIntent))],
        _ => throw new BrowserRuleException(BrowserRule.InvalidDeletionIntent)
    };

    internal static JsonObject Encode(SpaceDeletionState deletion) => new() {
        [Key.SpaceId] = WrappedIdentity(deletion.SpaceId),
        [Key.ProfileId] = BareIdentity(deletion.ProfileId),
        [Key.OperationId] = BareIdentity(deletion.Id)
    };

    private static JsonArray EncodeAll<T>(IEnumerable<T> records, Func<T, JsonObject> encode) =>
        new(records.Select(record => (JsonNode?)encode(record)).ToArray());

    #endregion
}
