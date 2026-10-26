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

    /// The members a folder's value carries; a record keeps what a newer build
    /// writes beside them.
    public static IReadOnlyList<string> Members { get; } = [
        StoredSessionCodec.Key.Id, StoredSessionCodec.Key.SpaceId, StoredSessionCodec.Key.Title, StoredSessionCodec.Key.Location,
        StoredSessionCodec.Key.Symbol, StoredSessionCodec.Key.Color, StoredSessionCodec.Key.ParentId, StoredSessionCodec.Key.IsCollapsed,
        StoredSessionCodec.Key.CollapseModifiedAt, StoredSessionCodec.Key.OrderAnchorTabId, SyncPayload.Key.OrderToken
    ];

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
    public static FolderPayload Read(SyncPayloadReader value) => new(value.WrappedIdentity(StoredSessionCodec.Key.Id),
        value.WrappedIdentity(StoredSessionCodec.Key.SpaceId),
        value.OptionalText(StoredSessionCodec.Key.Location) is { } location ? Placement(location) : TabPlacement.Saved,
        value.Text(StoredSessionCodec.Key.Title), value.OptionalText(StoredSessionCodec.Key.Symbol),
        value.Value[StoredSessionCodec.Key.Color] is { } color ? SpacePayload.Color(color) : FolderState.DefaultColor,
        value.OptionalWrappedIdentity(StoredSessionCodec.Key.ParentId), value.OptionalFlag(StoredSessionCodec.Key.IsCollapsed) ?? false,
        value.OptionalTime(StoredSessionCodec.Key.CollapseModifiedAt), value.OptionalWrappedIdentity(StoredSessionCodec.Key.OrderAnchorTabId),
        value.Text(Key.OrderToken));

    public override JsonObject EncodeValue(SyncPayloadForm form) {
        var value = new JsonObject {
            [StoredSessionCodec.Key.Id] = StoredSessionCodec.WrappedIdentity(Id),
            [StoredSessionCodec.Key.SpaceId] = StoredSessionCodec.WrappedIdentity(SpaceId),
            [StoredSessionCodec.Key.Location] = Location.Name,
            [StoredSessionCodec.Key.Title] = Title,
            [StoredSessionCodec.Key.Color] = StoredSessionCodec.Encode(Color)
        };
        Put(value, StoredSessionCodec.Key.Symbol, Symbol);
        PutWrapped(value, StoredSessionCodec.Key.ParentId, ParentId);
        value[StoredSessionCodec.Key.IsCollapsed] = IsCollapsed;
        Put(value, StoredSessionCodec.Key.CollapseModifiedAt, CollapseModifiedAt, form);
        PutWrapped(value, StoredSessionCodec.Key.OrderAnchorTabId, OrderAnchorTabId);
        value[Key.OrderToken] = OrderToken;
        return value;
    }

    /// The location a folder record spells: saved or open, and nothing else.
    private static TabPlacement Placement(string location) =>
        TabPlacement.Named(location) is { HoldsFolders: true } placement ? placement : throw new UnreadableSyncPayloadException();

    #endregion

    #region Actions - Validation

    public override void Validate() {
        RequireText(Title, SyncedText.FolderTitle.Limit);
        if (Symbol is { } symbol) RequireText(symbol, SyncedText.FolderSymbol.Limit);
        RequireOrderToken(OrderToken);
        if (ParentId == Id) throw new UnreadableSyncPayloadException();
    }

    #endregion
}
