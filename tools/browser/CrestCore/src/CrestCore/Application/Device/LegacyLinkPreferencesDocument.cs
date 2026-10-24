using System.Text.Json;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The link preferences earlier releases saved under
/// `crest.link-preferences.v1`, which the device store adopts once: a JSON
/// object whose fixed sets are spelled by `Name` and whose Space identities
/// are stored bare or as `{"rawValue": UUID}`, with the routes in order and
/// the remembered Spaces by site. A key the document lacks, or a value this
/// build cannot read, keeps its default; a route that does not read, repeats
/// an identity or comes past the limit is left out.
internal static class LegacyLinkPreferencesDocument {
    #region Static Variables

    private const string Destination = "externalLinkDestination";
    private const string DestinationSpace = "externalLinkSpaceID";
    private const string FocusesNewTabs = "focusesNewTabsOpenedFromLinks";
    private const string FollowsMovedTabs = "followsTabsMovedToAnotherSpace";
    private const string OpensPeekAutomatically = "automaticallyOpensPeek";
    private const string PeekModifier = "peekClickModifier";
    private const string DragsLinksToPeek = "dragsLinksToPeek";
    private const string ArchivePolicy = "quickWindowArchivePolicy";
    private const string RemembersSpaceBySite = "remembersQuickWindowSpaceBySite";
    private const string Routes = "routes";
    private const string RememberedSites = "rememberedQuickWindowSpacesBySite";
    private const string RouteId = "id";
    private const string RouteEnabled = "isEnabled";
    private const string RouteMatch = "match";
    private const string RoutePattern = "pattern";
    private const string RouteSpace = "destinationSpaceID";
    private const string WrappedIdentity = "rawValue";

    #endregion

    #region Actions - Adoption

    /// The preferences `document` holds over the defaults, or null when there
    /// is no document or it is not a JSON object.
    public static LinkPreferences? Read(byte[]? document) {
        if (document is null || document.Length == 0) return null;
        JsonDocument parsed;
        try {
            parsed = JsonDocument.Parse(document, new() { MaxDepth = 8 });
        } catch (JsonException) {
            return null;
        }
        using (parsed) {
            var root = parsed.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return null;
            var read = LinkPreferences.Default;
            read = read with {
                Destination = ExternalLinkDestination.Named(Text(root, Destination)) ?? read.Destination,
                DestinationSpaceId = Member(root, DestinationSpace) is { } space ? Identity(space) : null,
                PeekModifier = LinkPeekModifier.Named(Text(root, PeekModifier)) ?? read.PeekModifier,
                ArchivePolicy = QuickWindowArchivePolicy.Named(Text(root, ArchivePolicy)) ?? read.ArchivePolicy,
                Routes = ReadRoutes(root),
                RememberedSites = ReadSites(root)
            };
            foreach (var (behavior, key) in new[] {
                (LinkBehavior.FocusesNewTabs, FocusesNewTabs), (LinkBehavior.FollowsMovedTabs, FollowsMovedTabs),
                (LinkBehavior.OpensPeekAutomatically, OpensPeekAutomatically), (LinkBehavior.DragsLinksToPeek, DragsLinksToPeek),
                (LinkBehavior.RemembersSpaceBySite, RemembersSpaceBySite)
            })
                if (Member(root, key) is { ValueKind: JsonValueKind.True or JsonValueKind.False } flag)
                    read = behavior.Setting(read, flag.GetBoolean());
            return read;
        }
    }

    private static List<LinkRoute> ReadRoutes(JsonElement root) {
        var routes = new List<LinkRoute>();
        if (Member(root, Routes) is not { ValueKind: JsonValueKind.Array } values) return routes;
        foreach (var value in values.EnumerateArray()) {
            if (routes.Count == AddLinkRoute.MaximumRoutes) break;
            if (value.ValueKind != JsonValueKind.Object || Member(value, RouteId) is not { } idValue || Identity(idValue) is not { } id
                || routes.Any(route => route.Id == id)
                || Member(value, RouteEnabled) is not { ValueKind: JsonValueKind.True or JsonValueKind.False } enabled
                || LinkRouteMatch.Named(Text(value, RouteMatch)) is not { } match
                || Text(value, RoutePattern) is not { Length: <= EditLinkRoute.MaximumPatternLength } pattern
                || Member(value, RouteSpace) is not { } spaceValue || Identity(spaceValue) is not { } space)
                continue;
            routes.Add(new(id, enabled.GetBoolean(), match, pattern, space));
        }
        return routes;
    }

    private static List<RememberedSite> ReadSites(JsonElement root) {
        var sites = new List<RememberedSite>();
        if (Member(root, RememberedSites) is not { ValueKind: JsonValueKind.Object } values) return sites;
        foreach (var site in values.EnumerateObject())
            if (site.Name.Length > 0 && Identity(site.Value) is { } space) sites.Add(new(site.Name, space));
        return sites;
    }

    private static JsonElement? Member(JsonElement value, string name) => value.TryGetProperty(name, out var member) ? member : null;

    private static string? Text(JsonElement value, string name) =>
        Member(value, name) is { ValueKind: JsonValueKind.String } text ? text.GetString() : null;

    /// An identity stored bare or as `{"rawValue": UUID}`.
    private static Guid? Identity(JsonElement value) {
        if (value.ValueKind == JsonValueKind.Object) return Member(value, WrappedIdentity) is { } wrapped ? Identity(wrapped) : null;
        return value.ValueKind == JsonValueKind.String && Guid.TryParse(value.GetString(), out var id) ? id : null;
    }

    #endregion
}
