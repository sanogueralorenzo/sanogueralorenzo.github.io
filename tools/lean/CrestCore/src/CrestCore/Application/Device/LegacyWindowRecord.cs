using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// A window record an installed release kept in its defaults, in the format
/// its Swift `Codable` wrote: identities wrapped as `{"rawValue": UUID}` and
/// dictionaries keyed by an identity written as one array of keys and values
/// in turn. `CapturedSpaceIds` is null for a record written before windows
/// remembered the Spaces they had seen.
internal sealed record LegacyWindowRecord(Guid Id, Guid SelectedSpaceId, IReadOnlyDictionary<Guid, Guid> Tabs,
    IReadOnlySet<Guid>? CapturedSpaceIds, IReadOnlyDictionary<Guid, IReadOnlyList<double>> Shares, WindowLayout Layout) {
    #region Variables

    private const string IdKey = "id";
    private const string SelectedSpaceKey = "selectedSpaceID";
    private const string TabsKey = "selectedTabIDsBySpace";
    private const string CapturedKey = "capturedSpaceIDs";
    private const string SidebarWidthKey = "sidebarWidth";
    private const string SidebarPresentedKey = "sidebarIsPresented";
    private const string SharesKey = "splitColumnFractionsByGroup";
    private static readonly JsonDocumentOptions DocumentOptions = new() { MaxDepth = 64 };

    #endregion

    #region Actions - Decoding

    /// Every record `bytes` holds, oldest use first, as the release ordered
    /// them. A record that does not decode is left out; bytes that are not a
    /// list of records hold none.
    public static IReadOnlyList<LegacyWindowRecord> DecodeAll(byte[]? bytes) {
        if (bytes is null || bytes.Length == 0) return [];
        try {
            if (JsonNode.Parse(bytes, documentOptions: DocumentOptions) is not JsonArray records) return [];
            return [.. records.Select(Decode).OfType<LegacyWindowRecord>()];
        } catch (JsonException) {
            return [];
        }
    }

    private static LegacyWindowRecord? Decode(JsonNode? node) {
        try {
            if (node is not JsonObject value) return null;
            var id = Identity(value[IdKey]);
            var tabs = Pairs(value[TabsKey]).ToDictionary(pair => Identity(pair.Key), pair => Identity(pair.Value));
            var captured = value[CapturedKey] is JsonArray spaces ? spaces.Select(Identity).ToHashSet() : null;
            var shares = Pairs(value[SharesKey])
                .Select(pair => (GroupId: Identity(pair.Key),
                    Shares: Window.SplitShares([.. pair.Value!.AsArray().Select(share => share!.GetValue<double>())])))
                .Where(group => group.Shares is not null).ToDictionary(group => group.GroupId, group => group.Shares!);
            var layout = new WindowLayout(id, Number(value[SidebarWidthKey]), value[SidebarPresentedKey]?.GetValue<bool>());
            return new(id, Identity(value[SelectedSpaceKey]), tabs, captured, shares, layout);
        } catch (Exception error) when (StoredSession.IsUndecodable(error)) {
            return null;
        }
    }

    /// A Swift dictionary keyed by a type that is not a string: its keys and
    /// values in turn.
    private static IEnumerable<(JsonNode? Key, JsonNode? Value)> Pairs(JsonNode? node) {
        if (node is not JsonArray items) yield break;
        for (int index = 0; index + 1 < items.Count; index += 2) yield return (items[index], items[index + 1]);
    }

    private static Guid Identity(JsonNode? node) => StoredSessionCodec.Identity(node);

    private static double? Number(JsonNode? node) => node?.GetValue<double>();

    #endregion

    #region Actions - Folding

    /// The record the device store keeps for this window. A Space the window
    /// had seen without showing a tab shows none. A record written before
    /// windows remembered their Spaces first adopts `legacyTabs` in every
    /// Space of `spaces` it shows nothing in, and from then on has seen them
    /// all.
    public SavedWindow Record(IReadOnlyList<Guid> spaces, IReadOnlyDictionary<Guid, Guid> legacyTabs, long used) {
        var shown = Tabs.ToDictionary(entry => entry.Key, entry => (Guid?)entry.Value);
        var seen = CapturedSpaceIds ?? spaces.ToHashSet();
        if (CapturedSpaceIds is null)
            foreach (var spaceId in spaces.Where(spaceId => !shown.ContainsKey(spaceId) && legacyTabs.ContainsKey(spaceId)))
                shown[spaceId] = legacyTabs[spaceId];
        foreach (var spaceId in seen.Where(spaceId => !shown.ContainsKey(spaceId))) shown[spaceId] = null;
        return new(Id, SelectedSpaceId, [.. shown.Select(entry => new ShownTab(entry.Key, entry.Value))],
            [.. Shares.Select(entry => new SplitColumnShares(entry.Key, entry.Value))], used);
    }

    #endregion
}
