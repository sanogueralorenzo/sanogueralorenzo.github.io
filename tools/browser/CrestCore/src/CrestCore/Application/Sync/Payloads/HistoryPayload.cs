using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// A visit's synced value: its page and title, the first and last time the
/// page was visited, and how often.
internal sealed record HistoryPayload(
    Guid Id,
    Guid SpaceId,
    SyncedAddress Url,
    string Title,
    SyncTime FirstVisitedAt,
    SyncTime LastVisitedAt,
    long VisitCount) : SyncPayload {
    #region Static Variables

    private const int MaximumTitleBytes = 2_048;

    #endregion

    #region Variables

    public override Guid Id { get; } = Id;

    public override Guid SpaceId { get; } = SpaceId;
    public override SyncRecordKind Kind => SyncRecordKind.History;

    #endregion

    #region Actions - Coding

    public static HistoryPayload Read(SyncPayloadReader value) => new(value.Identity("id"), value.WrappedIdentity("spaceID"),
        new(value.Text("url")), value.Text("title"), value.Time("firstVisitedAt"), value.Time("lastVisitedAt"), value.Integer("visitCount"));

    public override JsonObject EncodeValue(SyncPayloadForm form) => new() {
        ["id"] = StoredSessionCodec.BareIdentity(Id),
        ["spaceID"] = StoredSessionCodec.WrappedIdentity(SpaceId),
        ["url"] = Url.Spelled ?? Url.Text,
        ["title"] = Title,
        ["firstVisitedAt"] = form.Seconds(FirstVisitedAt),
        ["lastVisitedAt"] = form.Seconds(LastVisitedAt),
        ["visitCount"] = VisitCount
    };

    #endregion

    #region Actions - Validation

    public override void Validate() {
        RequireWebAddress(Url);
        RequireText(Title, MaximumTitleBytes);
        if (VisitCount <= 0 || FirstVisitedAt.ReferenceSeconds > LastVisitedAt.ReferenceSeconds) throw new UnreadableSyncPayloadException();
    }

    public override void RequireSendable() => RequireSendableAddress(Url);

    #endregion
}
