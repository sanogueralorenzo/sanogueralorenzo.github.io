using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Additive fields in an accepted wire record belong to that record. A local
/// projection replaces fields this client understands and carries the rest
/// forward. Removed known fields and removed collection members stay removed.
internal static class NativeSyncCompatibility {
    #region Variables

    private sealed record Shape(string Names, Dictionary<string, Shape>? Children = null, Shape? Element = null, bool ById = false) {
        #region Constructors

        public Shape(IEnumerable<string> names, Dictionary<string, Shape>? children = null) : this(string.Join(' ', names), children) {
        }

        #endregion

        #region Variables

        public HashSet<string> Fields { get; } = Names.Split(' ', StringSplitOptions.RemoveEmptyEntries).ToHashSet(StringComparer.Ordinal);

        #endregion
    }

    private static readonly Shape Identity = new("rawValue");
    private static readonly Shape Color = new("red green blue alpha");

    private static readonly Shape Browsing = new(
        "searchProvider selectedSearchProviderID customSearchProviders searchSuggestionsEnabled searchFollowsDefault suggestionsFollowDefault currentTabCleanupPolicy contentBlockingPolicy dataRetention",
        new() { ["dataRetention"] = new("history archive downloads") });

    private static readonly Shape Tab = new(
        "id spaceID title nativeContent url savedURL symbol placement folderID splitGroupID orderToken lastActivatedAt positionModifiedAt customTitle titleModifiedAt",
        new() { ["id"] = Identity, ["spaceID"] = Identity, ["folderID"] = Identity, ["splitGroupID"] = Identity });

    private static readonly Dictionary<string, Shape> Values = new() {
        [SyncRecordKind.Space.Name] = new("id profileID name accent branding browsingPreferences credentialsEnabled credentialsEnabledModifiedAt splitGroups orderToken",
            new() { ["id"] = Identity, ["browsingPreferences"] = Browsing }),
        [SyncRecordKind.Folder.Name] = new("id spaceID title location symbol color parentID isCollapsed collapseModifiedAt orderAnchorTabID orderToken",
            new() { ["id"] = Identity, ["spaceID"] = Identity, ["parentID"] = Identity, ["orderAnchorTabID"] = Identity, ["color"] = Color }),
        [SyncRecordKind.Tab.Name] = Tab,
        [SyncRecordKind.History.Name] = new(HistoryPayload.Members, new() { [StoredSessionCodec.Key.SpaceId] = Identity }),
        [SyncRecordKind.Archive.Name] = new(ArchivePayload.Members, new() { [StoredSessionCodec.Key.Tab] = Tab })
    };

    #endregion

    #region Actions - Sync

    private static Shape List(Shape element, bool byId = false) => new("", Element: element, ById: byId);

    internal static JsonObject Preserve(JsonObject current, JsonObject? previous) {
        string kind = current[SyncPayload.Key.Type]!.GetValue<string>();
        if (previous?[SyncPayload.Key.Type]?.GetValue<string>() != kind) return current;
        return Merge(new([SyncPayload.Key.Type, SyncPayload.Key.Value], new() { [SyncPayload.Key.Value] = Values[kind] }), current, previous)
            .AsObject();
    }

    private static string? MemberId(JsonNode? value) {
        var id = value?["id"];
        if (id is JsonObject wrapper) id = wrapper["rawValue"];
        return id is JsonValue raw && raw.TryGetValue<string>(out var text) ? text.ToLowerInvariant() : null;
    }

    private static JsonNode Merge(Shape shape, JsonNode current, JsonNode? previous) {
        if (current is JsonObject fields && previous is JsonObject old) {
            var result = fields.DeepClone().AsObject();
            foreach (var (key, value) in old)
                if (!shape.Fields.Contains(key) && !fields.ContainsKey(key)) result[key] = value?.DeepClone();
            if (shape.Children is not null)
                foreach (var (key, child) in shape.Children)
                    if (fields[key] is { } value) result[key] = Merge(child, value, old[key]);
            return result;
        }
        if (current is JsonArray items && previous is JsonArray oldItems && shape.Element is { } element) {
            Dictionary<string, JsonNode?>? byId = shape.ById ? oldItems.Where(n => MemberId(n) is not null)
                .GroupBy(n => MemberId(n)!).ToDictionary(g => g.Key, g => g.Last(), StringComparer.Ordinal) : null;
            return new JsonArray(items.Select((item, index) => item is null ? null : Merge(element, item,
                byId is not null ? (MemberId(item) is { } id ? byId.GetValueOrDefault(id) : null)
                    : index < oldItems.Count ? oldItems[index] : null)).ToArray());
        }
        return current.DeepClone();
    }

    #endregion
}
