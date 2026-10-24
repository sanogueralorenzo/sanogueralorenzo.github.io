using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// A folder's synced value: where it lives, its title and look, its parent,
/// its disclosure with the clock of its last change, and its position.
internal sealed record FolderPayload(
    Guid Id,
    Guid SpaceId,
    TabPlacement Location,
    string Title,
    string? Symbol,
    BrandColor Color,
    Guid? ParentId,
    bool IsCollapsed,
    SyncTime? CollapseModifiedAt,
    Guid? OrderAnchorTabId,
    string OrderToken) : SyncPayload {
    #region Static Variables

    private const int MaximumTitleBytes = 512;
    private const int MaximumSymbolBytes = 128;

    #endregion

    #region Variables

    public override Guid Id { get; } = Id;

    public override Guid SpaceId { get; } = SpaceId;
    public override SyncRecordKind Kind => SyncRecordKind.Folder;

    /// Clients before open folders synced cannot place one, so a folder of
    /// the current tabs needs schema 2.
    public override int Schema => Location.IsDurable ? 1 : 2;

    #endregion

    #region Actions - Coding

    /// The folder `value` holds. One without a location is saved, without a
    /// symbol keeps none of its own and is drawn with the folder symbol,
    /// without a color takes the folder color, and without a disclosure is
    /// expanded.
    public static FolderPayload Read(SyncPayloadReader value) => new(value.WrappedIdentity("id"), value.WrappedIdentity("spaceID"),
        value.OptionalText("location") is { } location ? Placement(location) : TabPlacement.Saved,
        value.Text("title"), value.OptionalText("symbol"),
        value.Value["color"] is { } color ? SpacePayload.Color(color) : FolderState.DefaultColor,
        value.OptionalWrappedIdentity("parentID"), value.OptionalFlag("isCollapsed") ?? false, value.OptionalTime("collapseModifiedAt"),
        value.OptionalWrappedIdentity("orderAnchorTabID"), value.Text("orderToken"));

    public override JsonObject EncodeValue(SyncPayloadForm form) {
        var value = new JsonObject {
            ["id"] = StoredSessionCodec.WrappedIdentity(Id),
            ["spaceID"] = StoredSessionCodec.WrappedIdentity(SpaceId),
            ["location"] = Location.Name,
            ["title"] = Title,
            ["color"] = StoredSessionCodec.Encode(Color)
        };
        if (Symbol is { } symbol) value["symbol"] = symbol;
        PutWrapped(value, "parentID", ParentId);
        value["isCollapsed"] = IsCollapsed;
        Put(value, "collapseModifiedAt", CollapseModifiedAt, form);
        PutWrapped(value, "orderAnchorTabID", OrderAnchorTabId);
        value["orderToken"] = OrderToken;
        return value;
    }

    /// The location a folder record spells: saved or open, and nothing else.
    private static TabPlacement Placement(string location) =>
        TabPlacement.Named(location) is { HoldsFolders: true } placement ? placement : throw new UnreadableSyncPayloadException();

    #endregion

    #region Actions - Validation

    public override void Validate() {
        RequireText(Title, MaximumTitleBytes);
        if (Symbol is { } symbol) RequireText(symbol, MaximumSymbolBytes);
        RequireOrderToken(OrderToken);
        if (ParentId == Id) throw new UnreadableSyncPayloadException();
    }

    #endregion
}
