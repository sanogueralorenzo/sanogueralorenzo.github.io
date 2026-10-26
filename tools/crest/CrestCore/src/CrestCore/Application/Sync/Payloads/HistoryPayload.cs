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

    /// The members a visit's value carries; a record keeps what a newer build
    /// writes beside them.
    public static IReadOnlyList<string> Members { get; } = [
        StoredSessionCodec.Key.Id, StoredSessionCodec.Key.SpaceId, StoredSessionCodec.Key.Url, StoredSessionCodec.Key.Title,
        StoredSessionCodec.Key.FirstVisitedAt, StoredSessionCodec.Key.LastVisitedAt, StoredSessionCodec.Key.VisitCount
    ];

    #endregion

    #region Variables

    public override Guid Id { get; } = Id;

    public override Guid SpaceId { get; } = SpaceId;
    public override SyncRecordKind Kind => SyncRecordKind.History;

    #endregion

    #region Actions - Coding

    public static HistoryPayload Read(SyncPayloadReader value) => new(value.Identity(StoredSessionCodec.Key.Id),
        value.WrappedIdentity(StoredSessionCodec.Key.SpaceId), new(value.Text(StoredSessionCodec.Key.Url)),
        value.Text(StoredSessionCodec.Key.Title), value.Time(StoredSessionCodec.Key.FirstVisitedAt),
        value.Time(StoredSessionCodec.Key.LastVisitedAt), value.Integer(StoredSessionCodec.Key.VisitCount));

    public override JsonObject EncodeValue(SyncPayloadForm form) => new() {
        [StoredSessionCodec.Key.Id] = StoredSessionCodec.BareIdentity(Id),
        [StoredSessionCodec.Key.SpaceId] = StoredSessionCodec.WrappedIdentity(SpaceId),
        [StoredSessionCodec.Key.Url] = Url.Spelled ?? Url.Text,
        [StoredSessionCodec.Key.Title] = Title,
        [StoredSessionCodec.Key.FirstVisitedAt] = form.Seconds(FirstVisitedAt),
        [StoredSessionCodec.Key.LastVisitedAt] = form.Seconds(LastVisitedAt),
        [StoredSessionCodec.Key.VisitCount] = VisitCount
    };

    #endregion

    #region Actions - Validation

    public override void Validate() {
        RequireWebAddress(Url);
        RequireText(Title, SyncedText.HistoryTitle.Limit);
        if (VisitCount <= 0 || FirstVisitedAt.ReferenceSeconds > LastVisitedAt.ReferenceSeconds) throw new UnreadableSyncPayloadException();
    }

    public override void RequireSendable() => RequireSendableAddress(Url);

    #endregion
}
