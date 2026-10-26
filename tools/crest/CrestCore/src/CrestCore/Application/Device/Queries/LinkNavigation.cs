using CrestCore.Application;

namespace CrestCore.Contracts;

/// What following `Url` from a page does: load in the page, open in Peek, or
/// open in a new tab in front or behind. The page's tab, how a page with no
/// tab presents, the gesture and this device's link preferences decide it. A
/// page the core does not host loads the link itself.
public sealed record LinkNavigation(Guid PageId, string? Url, LinkGesture Gesture) : Query<LinkNavigationAnswer> {
    #region Actions - Answering

    /// An engine's link activation asks the device the same question.
    internal override LinkNavigationAnswer Answer(CrestApp app) => app.Device.Answer(this, app.Pages);

    #endregion
}
