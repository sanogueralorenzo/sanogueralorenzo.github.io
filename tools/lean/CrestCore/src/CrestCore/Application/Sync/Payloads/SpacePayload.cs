using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

internal sealed partial record SpacePayload(
    Guid Id,
    Guid ProfileId,
    string Name,
    BrowsingPreferences BrowsingPreferences,
    string OrderToken,
    bool IsGitHubFolderDismissed = false,
    SpaceColor? StoredColor = null) : SyncPayload {
    #region Static Variables

    private const int MaximumNameBytes = 128;

    #endregion

    #region Variables

    public override Guid Id { get; } = Id;
    public override SyncRecordKind Kind => SyncRecordKind.Space;

    public override Guid SpaceId => Id;
    public SpaceColor DotColor => StoredColor ?? SpaceColor.For(Id);

    #endregion

    #region Actions - Coding

    /// Reads a Space's identity, browsing preferences and sync metadata.
    public static SpacePayload Read(SyncPayloadReader value) {
        string name = value.Text("name");
        return new(value.WrappedIdentity("id"), value.Identity("profileID"), name,
            value.OptionalNested("browsingPreferences") is { } browsing ? ReadBrowsingPreferences(browsing)
                : StoredSessionCodec.DefaultBrowsingPreferences,
            value.Text("orderToken"), value.OptionalFlag("isGitHubFolderDismissed") ?? false,
            value.OptionalText("spaceColor") is { } color ? SpaceColor.Named(color) ?? throw new UnreadableSyncPayloadException() : null);
    }

    public override JsonObject EncodeValue(SyncPayloadForm form) {
        var value = new JsonObject {
            ["id"] = StoredSessionCodec.WrappedIdentity(Id),
            ["profileID"] = StoredSessionCodec.BareIdentity(ProfileId),
            ["name"] = Name,
            ["browsingPreferences"] = StoredSessionCodec.Encode(BrowsingPreferences)
        };
        if (IsGitHubFolderDismissed) value["isGitHubFolderDismissed"] = true;
        value["spaceColor"] = DotColor.Name;
        value["orderToken"] = OrderToken;
        return value;
    }

    #endregion

    #region Actions - Validation

    public override void Validate() {
        RequireText(Name, MaximumNameBytes);
        RequireOrderToken(OrderToken);
    }

    #endregion
}
