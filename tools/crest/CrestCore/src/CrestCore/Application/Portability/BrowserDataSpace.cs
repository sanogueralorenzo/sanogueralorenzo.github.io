using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// A Space as a Crest browser-data file keeps it: its name and look, folders,
/// tabs, splits, archive, history and browsing preferences, with the
/// identities the file spells. The Space's identity, profile, credential
/// preferences and lock never leave the device, and an import gives every
/// record a new identity.
internal sealed record BrowserDataSpace(string Name,
    IReadOnlyList<BrowserDataFolder> Folders, IReadOnlyList<BrowserDataTab> Tabs,
    IReadOnlyList<BrowserDataArchivedTab> ArchivedTabs, IReadOnlyList<BrowserDataHistoryEntry> History,
    BrowsingPreferences BrowsingPreferences, Guid? SelectedTabId) {
    #region Static Variables

    /// The most open and archived tabs a Space in a file holds.
    public const int MaximumTabs = 5_000;

    #endregion

    #region Actions - Reading

    public static BrowserDataSpace Read(BrowserDataValue value) {
        var browsing = StoredSessionCodec.DecodeBrowsingPreferences(value.Nested("browsingPreferences").Object);
        return new(value.Text("name"),
            [.. value.Items("folders").Select(BrowserDataFolder.Read)], [.. value.Items("tabs").Select(BrowserDataTab.Read)],
            [.. value.Items("archivedTabs").Select(BrowserDataArchivedTab.Read)],
            [.. value.Items("history").Select(BrowserDataHistoryEntry.Read)], browsing, value.OptionalIdentity("selectedTabID"));
    }

    /// The Space an import brings: every record with a new identity from
    /// `ids`, folders in the order the sidebar lists them, a Start Page opened
    /// `now` when it holds no tab, and each history address once. Throws
    /// `ArchiveInvalid` for anything a Space would not keep.
    public SpaceState Materialize(IIdSource ids, DateTimeOffset now) {
        ArgumentNullException.ThrowIfNull(ids);
        Require(ImportText.IsKept(Name, ImportText.MaximumSpaceName));
        Require(Folders.Count <= FolderTree.MaximumCount && Tabs.Count <= MaximumTabs && ArchivedTabs.Count <= MaximumTabs
            && History.Count <= HistoryEntryState.MaximumEntries);

        Dictionary<Guid, Guid> folderIds = [];
        foreach (var folder in Folders) Require(folderIds.TryAdd(folder.Id, ids.Next()));
        var folders = Folders.Select(folder => folder.Materialize(folderIds[folder.Id], folder.ParentId is { } parent
            ? parent != folder.Id && folderIds.TryGetValue(parent, out var mapped) ? mapped : throw BrowserDataValue.Invalid()
            : null)).ToArray();
        IReadOnlyList<FolderState> ordered;
        try {
            ordered = new FolderTree(folders).DisplayOrder();
        } catch (BrowserRuleException) {
            throw BrowserDataValue.Invalid();
        }

        Dictionary<Guid, Guid> splitIds = [];
        foreach (var split in Tabs.Select(tab => tab.SplitGroupId).OfType<Guid>()) splitIds.TryAdd(split, ids.Next());
        Dictionary<Guid, Guid> tabIds = [];
        List<TabState> tabs = [];
        var counts = new Dictionary<TabPlacement, int>();
        foreach (var tab in Tabs) {
            Require(!tabIds.ContainsKey(tab.Id));
            counts[tab.Placement] = counts.GetValueOrDefault(tab.Placement) + 1;
            Require(tab.Placement.Holds(counts[tab.Placement]));
            var kept = tab.Materialize(ids.Next(), folderIds, splitIds);
            tabIds[tab.Id] = kept.Id;
            tabs.Add(kept);
        }
        if (tabs.Count == 0) tabs.Add(BrowserDataTab.StartPage(ids.Next(), now));

        HashSet<Guid> seenArchived = [];
        var archived = ArchivedTabs.Select(entry => {
            Require(seenArchived.Add(entry.Tab.Id) && !tabIds.ContainsKey(entry.Tab.Id));
            return entry.Materialize(ids.Next());
        }).ToArray();
        var history = BrowserDataHistoryEntry.Materialize(History, HistoryEntryState.MaximumEntries, ids.Next);
        if (SelectedTabId is { } selected) Require(tabIds.ContainsKey(selected));

        var settings = new SpaceSettings(Name, BrowsingPreferences);
        return new(ids.Next(), ids.Next(), settings,
            [.. ordered.Select(folder => folder with {
                OrderAnchorTabId = folder.OrderAnchorTabId is { } anchor && tabIds.TryGetValue(anchor, out var tab) ? tab : null
            })],
            tabs, archived, history);
    }

    private static void Require(bool condition) {
        if (!condition) throw BrowserDataValue.Invalid();
    }

    #endregion

    #region Actions - Writing

    /// The Space as a file keeps it. Selection is window state, so a file
    /// never names one.
    public static BrowserDataSpace From(SpaceState space) {
        ArgumentNullException.ThrowIfNull(space);
        var settings = space.Settings;
        return new(settings.Name,
            [.. space.Folders.Select(BrowserDataFolder.From)], [.. space.Tabs.Select(BrowserDataTab.From)],
            [.. space.ArchivedTabs.Select(BrowserDataArchivedTab.From)],
            [.. space.History.Select(BrowserDataHistoryEntry.From)], settings.BrowsingPreferences, SelectedTabId: null);
    }

    public JsonObject Write() {
        var value = new JsonObject {
            ["name"] = Name
        };
        value["folders"] = new JsonArray([.. Folders.Select(folder => (JsonNode)folder.Write())]);
        value["tabs"] = new JsonArray([.. Tabs.Select(tab => (JsonNode)tab.Write())]);
        value["archivedTabs"] = new JsonArray([.. ArchivedTabs.Select(archived => (JsonNode)archived.Write())]);
        value["history"] = new JsonArray([.. History.Select(entry => (JsonNode)entry.Write())]);
        value["browsingPreferences"] = StoredSessionCodec.Encode(BrowsingPreferences);
        if (SelectedTabId is { } selected) value["selectedTabID"] = BrowserDataFile.Identity(selected);
        return value;
    }

    #endregion
}
