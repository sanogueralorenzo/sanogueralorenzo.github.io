using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

internal static partial class StoredSessionCodec {
    #region Variables

    /// What a folder without a title is called.
    internal const string UntitledFolder = "Folder";

    #endregion

    #region Actions - Tabs

    /// A tab. A native view keeps no address, a missing symbol is the one its
    /// content shows, and a placement or icon mode this build cannot name reads
    /// as saved and as unchosen, exactly as the native reader decides them.
    internal static TabState DecodeTab(JsonNode? node) {
        var value = Object(node);
        var native = value[Key.NativeContent] is JsonObject content
            ? new NativeTabContent(Text(content[Key.Kind]) ?? "", OptionalIdentity(content[Key.ResourceId])) : null;
        var url = native is null ? Text(value[Key.Url]) : null;
        var title = Text(value[Key.Title]);
        var shown = TabKind.FromStored(native?.Kind, url, title ?? "");
        return new(Identity(value[Key.Id]), title ?? shown.Title(url), url, native,
            native is null ? Text(value[Key.SavedUrl]) : null, Text(value[Key.Symbol]) ?? shown.Symbol,
            Text(value[Key.FaviconUrl]), value[Key.IconAccent] is JsonObject accent ? DecodeIconAccent(accent) : null,
            TabIconMode.Named(Text(value[Key.StoredIconMode])),
            TabPlacement.Named(Text(value[Key.Placement])) ?? TabPlacement.Saved,
            OptionalIdentity(value[Key.FolderId]), OptionalIdentity(value[Key.SplitGroupId]),
            Date(value[Key.LastActivatedAt]), OptionalDate(value[Key.PositionModifiedAt]),
            Text(value[Key.CustomTitle]), OptionalDate(value[Key.TitleModifiedAt]),
            Flag(value[Key.KeepsPageLoaded]) ?? false);
    }

    internal static JsonObject Encode(TabState tab) {
        var value = new JsonObject { [Key.Id] = WrappedIdentity(tab.Id), [Key.Title] = tab.Title };
        Put(value, Key.Url, tab.Url);
        if (tab.NativeContent is { } native) {
            var content = new JsonObject { [Key.Kind] = native.Kind };
            if (native.ResourceId is { } resource) content[Key.ResourceId] = BareIdentity(resource);
            value[Key.NativeContent] = content;
        }
        Put(value, Key.SavedUrl, tab.SavedUrl);
        value[Key.Symbol] = tab.Symbol;
        Put(value, Key.FaviconUrl, tab.FaviconUrl);
        if (tab.IconAccent is { } accent) value[Key.IconAccent] = Encode(accent);
        if (tab.StoredIconMode is { } mode) value[Key.StoredIconMode] = mode.Name;
        value[Key.Placement] = tab.Placement.Name;
        if (tab.FolderId is { } folder) value[Key.FolderId] = WrappedIdentity(folder);
        if (tab.SplitGroupId is { } group) value[Key.SplitGroupId] = WrappedIdentity(group);
        value[Key.LastActivatedAt] = Seconds(tab.LastActivatedAt);
        PutEdit(value, Key.PositionModifiedAt, tab.PositionModifiedAt);
        Put(value, Key.CustomTitle, tab.CustomTitle);
        PutEdit(value, Key.TitleModifiedAt, tab.TitleModifiedAt);
        value[Key.KeepsPageLoaded] = tab.KeepsPageLoaded;
        return value;
    }

    internal static TabIconAccent DecodeIconAccent(JsonObject value) =>
        new(Component(value, Key.Red), Component(value, Key.Green), Component(value, Key.Blue));

    internal static JsonObject Encode(TabIconAccent accent) =>
        new() { [Key.Red] = accent.Red, [Key.Green] = accent.Green, [Key.Blue] = accent.Blue };

    private static double Component(JsonObject value, string key) => value[key] is { } component ? Number(component) : 0;

    #endregion

    #region Actions - Archive

    /// An archived tab. Its reason is spelled so older builds can read it, with
    /// a deletion origin for the two deletions. An unknown cause is a close.
    internal static ArchivedTabState DecodeArchivedTab(JsonNode? node) {
        var value = Object(node);
        var reason = ArchiveReason.Stored(Text(value[Key.Reason]), Text(value[Key.DeletionOrigin])) ?? ArchiveReason.Closed;
        return new(DecodeTab(value[Key.Tab]), Date(value[Key.ArchivedAt]), reason);
    }

    internal static JsonObject Encode(ArchivedTabState archived) {
        var value = new JsonObject {
            [Key.Tab] = Encode(archived.Tab),
            [Key.ArchivedAt] = Seconds(archived.ArchivedAt),
            [Key.Reason] = archived.Reason.StoredReason
        };
        Put(value, Key.DeletionOrigin, archived.Reason.DeletionOrigin);
        return value;
    }

    #endregion

    #region Actions - Folders and splits

    /// A folder. Anything but an open folder is saved; a folder without a title
    /// reads as "Folder".
    internal static FolderState DecodeFolder(JsonNode? node) {
        var value = Object(node);
        return new(Identity(value[Key.Id]),
            TabPlacement.Named(Text(value[Key.Location])) == TabPlacement.Current ? TabPlacement.Current : TabPlacement.Saved,
            Text(value[Key.Title]) ?? UntitledFolder, Text(value[Key.Symbol]),
            value[Key.Color] is JsonObject color ? DecodeColor(color) : null, OptionalIdentity(value[Key.ParentId]),
            Flag(value[Key.IsCollapsed]) ?? false, OptionalDate(value[Key.CollapseModifiedAt]),
            OptionalIdentity(value[Key.OrderAnchorTabId]));
    }

    internal static JsonObject Encode(FolderState folder) {
        var value = new JsonObject {
            [Key.Id] = WrappedIdentity(folder.Id),
            [Key.Location] = folder.Location.Name,
            [Key.Title] = folder.Title
        };
        Put(value, Key.Symbol, folder.Symbol);
        if (folder.Color is { } color) value[Key.Color] = Encode(color);
        if (folder.ParentId is { } parent) value[Key.ParentId] = WrappedIdentity(parent);
        value[Key.IsCollapsed] = folder.IsCollapsed;
        Put(value, Key.CollapseModifiedAt, folder.CollapseModifiedAt);
        if (folder.OrderAnchorTabId is { } anchor) value[Key.OrderAnchorTabId] = WrappedIdentity(anchor);
        return value;
    }

    internal static SplitGroupState DecodeSplitGroup(JsonNode? node) {
        var value = Object(node);
        return new(Identity(value[Key.Id]), Text(value[Key.CustomTitle]), OptionalDate(value[Key.TitleModifiedAt]),
            Text(value[Key.CustomIconSymbol]), OptionalDate(value[Key.IconModifiedAt]),
            value[Key.Tint] is JsonObject tint ? DecodeColor(tint) : null, OptionalDate(value[Key.TintModifiedAt]));
    }

    internal static JsonObject Encode(SplitGroupState group) {
        var value = new JsonObject { [Key.Id] = WrappedIdentity(group.Id) };
        Put(value, Key.CustomTitle, group.CustomTitle);
        PutEdit(value, Key.TitleModifiedAt, group.TitleModifiedAt);
        Put(value, Key.CustomIconSymbol, group.CustomIconSymbol);
        PutEdit(value, Key.IconModifiedAt, group.IconModifiedAt);
        if (group.Tint is { } tint) value[Key.Tint] = Encode(tint);
        PutEdit(value, Key.TintModifiedAt, group.TintModifiedAt);
        return value;
    }

    /// A color; alpha defaults to opaque.
    internal static BrandColor DecodeColor(JsonObject value) => new(Component(value, Key.Red), Component(value, Key.Green),
        Component(value, Key.Blue), value[Key.Alpha] is { } alpha ? Number(alpha) : 1);

    internal static JsonObject Encode(BrandColor color) =>
        new() { [Key.Red] = color.Red, [Key.Green] = color.Green, [Key.Blue] = color.Blue, [Key.Alpha] = color.Alpha };

    #endregion

    #region Actions - History

    internal static HistoryEntryState DecodeHistoryEntry(JsonNode? node) {
        var value = Object(node);
        return new(Identity(value[Key.Id]),
            Text(value[Key.Url]) ?? throw new BrowserRuleException(BrowserRule.InvalidSavedUrl),
            Text(value[Key.Title]) ?? "", Date(value[Key.FirstVisitedAt]), Date(value[Key.LastVisitedAt]),
            Integer(value[Key.VisitCount]) ?? 1);
    }

    internal static JsonObject Encode(HistoryEntryState entry) => new() {
        [Key.Id] = BareIdentity(entry.Id),
        [Key.Url] = entry.Url,
        [Key.Title] = entry.Title,
        [Key.FirstVisitedAt] = Seconds(entry.FirstVisitedAt),
        [Key.LastVisitedAt] = Seconds(entry.LastVisitedAt),
        [Key.VisitCount] = entry.VisitCount
    };

    #endregion
}
