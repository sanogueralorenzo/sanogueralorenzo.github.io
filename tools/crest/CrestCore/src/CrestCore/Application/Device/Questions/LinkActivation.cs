using CrestCore.Application;

namespace CrestCore.Contracts;

/// What a person's activation of the link to `Url` in a page does: the page
/// loads it, Peek opens it, or a new tab opens it in front or behind. The
/// page's tab, how a page without one presents, `Gesture` and this device's
/// link preferences decide it, as they decide a `LinkNavigation`. A page the
/// core does not host loads the link itself.
public sealed record LinkActivation(Guid PageId, string Url, LinkGesture Gesture) : EngineQuestion<LinkNavigationAnswer> {
    #region Actions - Answering

    /// A question about a page the core does not host on that engine leaves
    /// the page to the engine: its link loads in the page.
    internal override LinkNavigationAnswer Answer(CrestApp app, Engine engine) =>
        ReferenceEquals(app.Pages.Hosted(PageId)?.Engine, engine)
            ? app.Device.Answer(new LinkNavigation(PageId, Url, Gesture), app.Pages)
            : new LinkNavigationAnswer(LinkNavigationDecision.Navigate);

    #endregion
}
