using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record CaptureDecision(Guid SpaceId, SiteOrigin Origin, SitePermission Media) : Query<SitePermissionAnswer> {
    #region Actions - Answering

    /// The prompts ask the device the same question.
    internal override SitePermissionAnswer Answer(CrestApp app) => app.Device.Answer(this);

    #endregion
}
