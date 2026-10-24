using CrestCore.Application;

namespace CrestCore.Contracts;

/// The document asked for an unsupported key system. Prepare an automatic
/// move once per document, honoring its before-unload decision first.
public sealed record ProtectedMediaUnavailable(Guid PageId, KeySystem KeySystem) : PageEvent(PageId) {
    #region Actions - Pages

    /// An explicit site choice wins over automatic fallback. A page that
    /// moved once never bounces back because the other engine also probes.
    internal override void Apply(Pages pages, Page page, PageTurn turn) {
        if (page.Phase != PagePhase.Live || pages.Shown(page) is not { } space || page.MovedFor(RehostReason.ProtectedMedia)
            || pages.Engines.PlayingProtectedMedia(page.Engine) is not { } fallback
            || page.DocumentAddress is not { } address || new WebAddress(address).Origin is not { } origin
            || pages.Device.ChosenEngine(space.Id, origin) is not null || turn.Closing.Underway is not null)
            return;
        if (page.TryProtectedMediaFallback())
            turn.Closing.Move(page, fallback, address, RehostReason.ProtectedMedia, remembersSite: true, turn);
    }

    #endregion
}
