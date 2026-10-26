using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record LinkActivation(Guid PageId, string Url, LinkGesture Gesture) : EngineQuestion<LinkNavigationAnswer> {
    #region Actions - Answering

    /// A question about a page the core does not host on that engine leaves
    /// the page to the engine: its link loads in the page.
    internal override LinkNavigationAnswer Answer(CrestApp app, Engine engine) =>
        ReferenceEquals(app.Pages.Hosted(PageId)?.Engine, engine)
            ? new LinkNavigation(PageId, Url, Gesture).Answer(app)
            : new LinkNavigationAnswer(LinkNavigationDecision.Navigate);

    #endregion
}
