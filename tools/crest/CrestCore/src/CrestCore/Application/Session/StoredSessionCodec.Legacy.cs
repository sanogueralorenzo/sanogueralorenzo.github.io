using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

internal static partial class StoredSessionCodec {
    #region Variables

    private const string LegacyTabGroups = "currentTabFolders";
    private const string FaviconData = "faviconData";
    private const string LegacyFolderSymbol = "folder";

    #endregion

    #region Actions - Installed releases

    /// A session an installed release kept: the stored format, where each tab
    /// group the releases before folders stored becomes an open folder once.
    /// A group becomes a folder only when its Space has no folder with its
    /// identity and at least one of its tabs is open and in no folder; those
    /// tabs move into it.
    internal static SessionState DecodeInstalledSession(JsonObject document) {
        var session = DecodeSession(document);
        foreach (var group in Items(document[LegacyTabGroups]).Select(Object)) {
            var spaceId = Identity(group[Key.SpaceId]);
            var folderId = Identity(group[Key.FolderId]);
            var members = Items(group[Key.Tabs]).Select(Identity).ToHashSet();
            var spaces = session.Spaces.ToArray();
            int index = Array.FindIndex(spaces, space => space.Id == spaceId);
            if (index < 0 || spaces[index].Folders.Any(folder => folder.Id == folderId)) continue;
            var space = spaces[index];
            bool Joins(TabState tab) => members.Contains(tab.Id) && !tab.Placement.IsDurable && tab.FolderId is null;
            if (!space.Tabs.Any(Joins)) continue;
            var folder = new FolderState(folderId, TabPlacement.Current, Text(group[Key.Title]) ?? UntitledFolder,
                LegacyFolderSymbol, (TabGroupColor.Named(TolerantText(group[Key.Color])) ?? TabGroupColor.Grey).Color,
                IsCollapsed: TolerantFlag(group[Key.IsCollapsed]) ?? false);
            spaces[index] = space with {
                Folders = [.. space.Folders, folder],
                Tabs = [.. space.Tabs.Select(tab => Joins(tab) ? tab with { FolderId = folderId } : tab)]
            };
            session = session with { Spaces = [.. spaces] };
        }
        return session;
    }

    /// The images the tabs of a whole-graph session carry inside it. A tab
    /// without an image, or with one that is not base64, carries none.
    internal static IReadOnlyList<TabFavicon> DecodeInlineFavicons(JsonObject document) {
        var favicons = new List<TabFavicon>();
        foreach (var space in Items(document[Key.Spaces]).OfType<JsonObject>())
            foreach (var tab in Items(space[Key.Tabs]).OfType<JsonObject>()) {
                if (TolerantText(tab[FaviconData]) is not { } encoded) continue;
                var image = new byte[encoded.Length];
                if (!Convert.TryFromBase64String(encoded, image, out int length) || length == 0) continue;
                favicons.Add(new TabFavicon(Identity(tab[Key.Id]), image[..length]));
            }
        return favicons;
    }

    /// One Space's history as an installed release kept it beside the session:
    /// the newest entries it may keep, or none when the bytes do not decode.
    internal static IReadOnlyList<HistoryEntryState> DecodeInstalledHistory(ReadOnlySpan<byte> entries) {
        try {
            return JsonNode.Parse(entries, documentOptions: new() { MaxDepth = 64 }) is JsonArray history
                ? [.. history.Take(HistoryEntryState.MaximumEntries).Select(DecodeHistoryEntry)]
                : [];
        } catch (Exception error) when (error is System.Text.Json.JsonException or BrowserRuleException or InvalidOperationException
            or FormatException) {
            return [];
        }
    }

    #endregion
}
