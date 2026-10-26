using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// A tab's synced value: its page or native view, title and symbol, where it
/// sits, its split and folder, and the clocks of its last move and rename.
internal sealed record TabPayload(
    Guid Id,
    Guid SpaceId,
    string Title,
    NativeTabContent? NativeContent,
    SyncedAddress? Url,
    SyncedAddress? SavedUrl,
    string Symbol,
    TabPlacement Placement,
    Guid? FolderId,
    Guid? SplitGroupId,
    string OrderToken,
    SyncTime LastActivatedAt,
    SyncTime? PositionModifiedAt,
    string? CustomTitle,
    SyncTime? TitleModifiedAt) : SyncPayload {
    #region Static Variables

    /// The members a tab's value carries; a record keeps what a newer build
    /// writes beside them.
    public static IReadOnlyList<string> Members { get; } = [
        StoredSessionCodec.Key.Id, StoredSessionCodec.Key.SpaceId, StoredSessionCodec.Key.Title, StoredSessionCodec.Key.NativeContent,
        StoredSessionCodec.Key.Url, StoredSessionCodec.Key.SavedUrl, StoredSessionCodec.Key.Symbol, StoredSessionCodec.Key.Placement,
        StoredSessionCodec.Key.FolderId, StoredSessionCodec.Key.SplitGroupId, SyncPayload.Key.OrderToken, StoredSessionCodec.Key.LastActivatedAt,
        StoredSessionCodec.Key.PositionModifiedAt, StoredSessionCodec.Key.CustomTitle, StoredSessionCodec.Key.TitleModifiedAt
    ];

    private const int MaximumNativeKindBytes = 128;

    /// The blank page older builds synced, whose records stay readable so
    /// staging can retire them.
    private const string BlankPage = "about:blank";

    #endregion

    #region Variables

    public override Guid Id { get; } = Id;

    public override Guid SpaceId { get; } = SpaceId;
    public override SyncRecordKind Kind => SyncRecordKind.Tab;

    /// Clients before native views synced cannot show one, so a native tab
    /// needs schema 3; clients before open folders synced cannot place a
    /// current tab in a folder, so one needs schema 2.
    public override int Schema => NativeContent is not null ? 3 : !Placement.IsDurable && FolderId is not null ? 2 : 1;

    #endregion

    #region Actions - Coding

    /// The tab `value` holds.
    public static TabPayload Read(SyncPayloadReader value) => new(value.WrappedIdentity("id"), value.WrappedIdentity("spaceID"),
        value.Text("title"),
        value.OptionalNested("nativeContent") is { } native ? new(native.Text("kind"), native.OptionalIdentity("resourceID")) : null,
        value.OptionalText("url") is { } url ? new SyncedAddress(url) : null,
        value.OptionalText("savedURL") is { } saved ? new SyncedAddress(saved) : null,
        value.Text("symbol"), value.Named("placement", TabPlacement.Named),
        value.OptionalWrappedIdentity("folderID"), value.OptionalWrappedIdentity("splitGroupID"), value.Text("orderToken"),
        value.Time("lastActivatedAt"), value.OptionalTime("positionModifiedAt"), value.OptionalText("customTitle"),
        value.OptionalTime("titleModifiedAt"));

    public override JsonObject EncodeValue(SyncPayloadForm form) {
        var value = new JsonObject {
            [StoredSessionCodec.Key.Id] = StoredSessionCodec.WrappedIdentity(Id),
            [StoredSessionCodec.Key.SpaceId] = StoredSessionCodec.WrappedIdentity(SpaceId),
            [StoredSessionCodec.Key.Title] = Title
        };
        Put(value, StoredSessionCodec.Key.Url, Url is { } url ? url.Spelled ?? url.Text : null);
        if (NativeContent is { } native) {
            var content = new JsonObject { [StoredSessionCodec.Key.Kind] = native.Kind };
            if (native.ResourceId is { } resource) content[StoredSessionCodec.Key.ResourceId] = StoredSessionCodec.BareIdentity(resource);
            value[StoredSessionCodec.Key.NativeContent] = content;
        }
        Put(value, "savedURL", SavedUrl is { } saved ? saved.Spelled ?? saved.Text : null);
        value["symbol"] = Symbol;
        value["placement"] = Placement.Name;
        PutWrapped(value, "folderID", FolderId);
        PutWrapped(value, "splitGroupID", SplitGroupId);
        value["orderToken"] = OrderToken;
        value["lastActivatedAt"] = form.Seconds(LastActivatedAt);
        Put(value, "positionModifiedAt", PositionModifiedAt, form);
        Put(value, "customTitle", CustomTitle);
        Put(value, "titleModifiedAt", TitleModifiedAt, form);
        return value;
    }

    #endregion

    #region Actions - Validation

    public override void Validate() {
        if (NativeContent is { } native) {
            RequireText(native.Kind, MaximumNativeKindBytes);
            if (Url is not null || SavedUrl is not null) throw new UnreadableSyncPayloadException();
        }
        RequireText(Title, SyncedText.TabTitle.Limit);
        if (CustomTitle is { } rename) RequireText(rename, SyncedText.TabCustomTitle.Limit);
        RequireText(Symbol, SyncedText.TabSymbol.Limit);
        RequireOrderToken(OrderToken);
        if (Url is { } url && url.Text != BlankPage) RequireWebAddress(url);
        if (!Placement.HoldsFolders && FolderId is not null) throw new UnreadableSyncPayloadException();
    }

    public override void RequireSendable() {
        if (Url is { } url && url.Text != BlankPage) RequireSendableAddress(url);
    }

    /// Throws `UnreadableSyncPayloadException` when the tab cannot be an
    /// archived tab: one still pinned or saved, in a folder, or in a split.
    public void RequireArchivable() {
        if (Placement.IsDurable || FolderId is not null || SplitGroupId is not null) throw new UnreadableSyncPayloadException();
    }

    #endregion
}
