using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

/// An archived tab's synced value: the tab as it was when it left, when it
/// was archived, and why. An archived tab shares the identity of the tab it
/// was.
internal sealed record ArchivePayload(TabPayload Tab, SyncTime ArchivedAt, ArchiveReason Reason) : SyncPayload {
    #region Variables

    public override SyncRecordKind Kind => SyncRecordKind.Archive;

    public override Guid Id => Tab.Id;

    public override Guid SpaceId => Tab.SpaceId;

    /// Clients before native views synced cannot show an archived one.
    public override int Schema => Tab.NativeContent is not null ? 3 : 1;

    #endregion

    #region Actions - Coding

    public static ArchivePayload Read(SyncPayloadReader value) =>
        new(TabPayload.Read(value.Nested("tab")), value.Time("archivedAt"), value.Named("reason", ArchiveReason.Named));

    public override JsonObject EncodeValue(SyncPayloadForm form) => new() {
        ["tab"] = Tab.EncodeValue(form),
        ["archivedAt"] = form.Seconds(ArchivedAt),
        ["reason"] = Reason.Name
    };

    #endregion

    #region Actions - Validation

    /// The tab validates as a live one would, and has left its placement's
    /// folder and split: a lone record can carry that much of a split's rules.
    public override void Validate() {
        Tab.Validate();
        Tab.RequireArchivable();
    }

    public override void RequireSendable() => Tab.RequireSendable();

    #endregion
}
