using CrestCore.Application;

namespace CrestCore.Contracts;

/// The choice that answers one request for `Permission` at `Origin` in a
/// Space: the session choice, then the saved one, for `Detail` first and then
/// for the whole site. A locked Space, and an origin or detail the rules
/// cannot read, answer Ask.
public sealed record SiteDecision(Guid SpaceId, SiteOrigin Origin, SitePermission Permission, string? Detail)
    : Query<SitePermissionAnswer> {
    #region Actions - Answering

    /// The prompts ask the device the same question.
    internal override SitePermissionAnswer Answer(CrestApp app) => app.Device.Answer(this);

    #endregion
}
