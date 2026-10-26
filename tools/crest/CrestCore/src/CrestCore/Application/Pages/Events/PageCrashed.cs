using CrestCore.Application;

namespace CrestCore.Contracts;

/// A page's renderer stopped: it crashed, or the system ended it. The document
/// it showed is gone, and the core decides whether the engine brings it back.
/// `Domain` and `Code` are the engine's own reason, which a failure page shows
/// as technical details and nothing branches on.
public sealed record PageCrashed(Guid PageId, string Domain, long Code) : PageEvent(PageId) {
    #region Actions - Pages

    /// A live page comes back by the core's crash recovery, which asks its
    /// engine to bring it back; a page nobody sees comes back once a window
    /// shows it.
    internal override void Apply(Pages pages, Page page, PageTurn turn) {
        if (page.Phase != PagePhase.Live) return;
        var recovers = false;
        pages.Update(page, turn.Changes, () => recovers = page.Crash(pages.IsShown(page), Domain, Code));
        if (recovers) turn.Issue(page.Engine, new RecoverPage(page.Id));
    }

    #endregion
}
