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

    /// The members a tab's value carries; a record keeps what a newer build
    /// writes beside them.
    public static IReadOnlyList<string> Members { get; } = [
        StoredSessionCodec.Key.Id, StoredSessionCodec.Key.SpaceId, StoredSessionCodec.Key.Title, StoredSessionCodec.Key.NativeContent,
        StoredSessionCodec.Key.Url, StoredSessionCodec.Key.SavedUrl, StoredSessionCodec.Key.Symbol, StoredSessionCodec.Key.Placement,
        StoredSessionCodec.Key.FolderId, StoredSessionCodec.Key.SplitGroupId, SyncPayload.Key.OrderToken, StoredSessionCodec.Key.LastActivatedAt,
        StoredSessionCodec.Key.PositionModifiedAt, StoredSessionCodec.Key.CustomTitle, StoredSessionCodec.Key.TitleModifiedAt,
        StoredSessionCodec.Key.KeepsPageLoaded
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

    /// The tab `value` holds. One that does not say keeps its page loaded
    /// only while the app decides to.
    public static TabPayload Read(SyncPayloadReader value) => new(value.WrappedIdentity(StoredSessionCodec.Key.Id),
        value.WrappedIdentity(StoredSessionCodec.Key.SpaceId), value.Text(StoredSessionCodec.Key.Title),
        value.OptionalNested(StoredSessionCodec.Key.NativeContent) is { } native
            ? new(native.Text(StoredSessionCodec.Key.Kind), native.OptionalIdentity(StoredSessionCodec.Key.ResourceId)) : null,
        value.OptionalText(StoredSessionCodec.Key.Url) is { } url ? new SyncedAddress(url) : null,
        value.OptionalText(StoredSessionCodec.Key.SavedUrl) is { } saved ? new SyncedAddress(saved) : null,
        value.Text(StoredSessionCodec.Key.Symbol), value.Named(StoredSessionCodec.Key.Placement, TabPlacement.Named),
        value.OptionalWrappedIdentity(StoredSessionCodec.Key.FolderId), value.OptionalWrappedIdentity(StoredSessionCodec.Key.SplitGroupId),
        value.Text(Key.OrderToken), value.Time(StoredSessionCodec.Key.LastActivatedAt),
        value.OptionalTime(StoredSessionCodec.Key.PositionModifiedAt), value.OptionalText(StoredSessionCodec.Key.CustomTitle),
        value.OptionalTime(StoredSessionCodec.Key.TitleModifiedAt), value.OptionalFlag(StoredSessionCodec.Key.KeepsPageLoaded) ?? false);

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
        Put(value, StoredSessionCodec.Key.SavedUrl, SavedUrl is { } saved ? saved.Spelled ?? saved.Text : null);
        value[StoredSessionCodec.Key.Symbol] = Symbol;
        value[StoredSessionCodec.Key.Placement] = Placement.Name;
        PutWrapped(value, StoredSessionCodec.Key.FolderId, FolderId);
        PutWrapped(value, StoredSessionCodec.Key.SplitGroupId, SplitGroupId);
        value[Key.OrderToken] = OrderToken;
        value[StoredSessionCodec.Key.LastActivatedAt] = form.Seconds(LastActivatedAt);
        Put(value, StoredSessionCodec.Key.PositionModifiedAt, PositionModifiedAt, form);
        Put(value, StoredSessionCodec.Key.CustomTitle, CustomTitle);
        Put(value, StoredSessionCodec.Key.TitleModifiedAt, TitleModifiedAt, form);
        value[StoredSessionCodec.Key.KeepsPageLoaded] = KeepsPageLoaded;
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
