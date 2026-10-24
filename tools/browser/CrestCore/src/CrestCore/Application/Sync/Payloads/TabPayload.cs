using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// A tab's synced value: its page or native view, title and symbol, where it
/// sits, its split and folder, the clocks of its last move and rename, and
/// whether its page stays loaded.
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
    SyncTime? TitleModifiedAt,
    bool KeepsPageLoaded) : SyncPayload {
    #region Static Variables

    private const int MaximumTitleBytes = 2_048;
    private const int MaximumSymbolBytes = 128;
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

    /// The tab `value` holds. One that does not say keeps its page loaded
    /// only while the app decides to.
    public static TabPayload Read(SyncPayloadReader value) => new(value.WrappedIdentity("id"), value.WrappedIdentity("spaceID"),
        value.Text("title"),
        value.OptionalNested("nativeContent") is { } native ? new(native.Text("kind"), native.OptionalIdentity("resourceID")) : null,
        value.OptionalText("url") is { } url ? new SyncedAddress(url) : null,
        value.OptionalText("savedURL") is { } saved ? new SyncedAddress(saved) : null,
        value.Text("symbol"), value.Named("placement", TabPlacement.Named),
        value.OptionalWrappedIdentity("folderID"), value.OptionalWrappedIdentity("splitGroupID"), value.Text("orderToken"),
        value.Time("lastActivatedAt"), value.OptionalTime("positionModifiedAt"), value.OptionalText("customTitle"),
        value.OptionalTime("titleModifiedAt"), value.OptionalFlag("keepsPageLoaded") ?? false);

    public override JsonObject EncodeValue(SyncPayloadForm form) {
        var value = new JsonObject {
            ["id"] = StoredSessionCodec.WrappedIdentity(Id),
            ["spaceID"] = StoredSessionCodec.WrappedIdentity(SpaceId),
            ["title"] = Title
        };
        Put(value, "url", Url is { } url ? url.Spelled ?? url.Text : null);
        if (NativeContent is { } native) {
            var content = new JsonObject { ["kind"] = native.Kind };
            if (native.ResourceId is { } resource) content["resourceID"] = StoredSessionCodec.BareIdentity(resource);
            value["nativeContent"] = content;
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
        value["keepsPageLoaded"] = KeepsPageLoaded;
        return value;
    }

    #endregion

    #region Actions - Validation

    public override void Validate() {
        if (NativeContent is { } native) {
            RequireText(native.Kind, MaximumNativeKindBytes);
            if (Url is not null || SavedUrl is not null) throw new UnreadableSyncPayloadException();
        }
        RequireText(Title, MaximumTitleBytes);
        if (CustomTitle is { } rename) RequireText(rename, MaximumTitleBytes);
        RequireText(Symbol, MaximumSymbolBytes);
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
