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
    private static readonly Shape Charge = new("kind value style");

    private static readonly Shape Crest = new(
        "backplate fieldDivision ordinary trim symbol chargeLayout backplateColorIndex secondaryFieldColorIndex ordinaryColorIndex trimColorIndex symbolColorIndex edgeColorIndex palette charge plateScale edgeWidth divisionCount finish ordinaryWidth trimWeight trimDetail chargeScale chargeOffset chargeWeight startingPresetID sheenAngle sealTeeth showsOutline depth",
        new() { ["palette"] = List(Color), ["charge"] = Charge });

    private static readonly Shape Branding = new(
        "colors bannerPattern bannerStrength readabilityFade keepsControlsReadable themeMode gradientAngle showsTexture iconStyle symbolColor crest renderingVersion folderColorIntensity textColorMode hasCustomAppearance",
        new() { ["colors"] = List(Color), ["symbolColor"] = Color, ["crest"] = Crest });

    private static readonly Shape SearchProvider = new("id name searchURLTemplate suggestionURLTemplate");

    private static readonly Shape Browsing = new(
        "searchProvider selectedSearchProviderID customSearchProviders searchSuggestionsEnabled searchFollowsDefault suggestionsFollowDefault currentTabCleanupPolicy contentBlockingPolicy dataRetention",
        new() { ["customSearchProviders"] = List(SearchProvider, true), ["dataRetention"] = new("history archive downloads") });

    private static readonly Shape Group = new(SplitGroupPayload.Members,
        new() { [StoredSessionCodec.Key.Id] = Identity, [StoredSessionCodec.Key.Tint] = Color });

    private static readonly Shape Tab = new(TabPayload.Members, new() {
        [StoredSessionCodec.Key.Id] = Identity,
        [StoredSessionCodec.Key.SpaceId] = Identity,
        [StoredSessionCodec.Key.FolderId] = Identity,
        [StoredSessionCodec.Key.SplitGroupId] = Identity
    });

    private static readonly Dictionary<string, Shape> Values = new() {
        [SyncRecordKind.Space.Name] = new(SpacePayload.Members, new() {
            [StoredSessionCodec.Key.Id] = Identity,
            [StoredSessionCodec.Key.Branding] = Branding,
            [StoredSessionCodec.Key.BrowsingPreferences] = Browsing,
            [StoredSessionCodec.Key.SplitGroups] = List(Group, true)
        }),
        [SyncRecordKind.Folder.Name] = new(FolderPayload.Members, new() {
            [StoredSessionCodec.Key.Id] = Identity,
            [StoredSessionCodec.Key.SpaceId] = Identity,
            [StoredSessionCodec.Key.ParentId] = Identity,
            [StoredSessionCodec.Key.OrderAnchorTabId] = Identity,
            [StoredSessionCodec.Key.Color] = Color
        }),
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
