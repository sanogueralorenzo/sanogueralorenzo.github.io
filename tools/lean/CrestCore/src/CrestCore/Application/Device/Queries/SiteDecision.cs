using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record SiteDecision(Guid SpaceId, SiteOrigin Origin, SitePermission Permission, string? Detail)
    : Query<SitePermissionAnswer> {
    #region Actions - Answering

    /// The prompts ask the device the same question.
    internal override SitePermissionAnswer Answer(CrestApp app) => app.Device.Answer(this);

    #endregion
}
