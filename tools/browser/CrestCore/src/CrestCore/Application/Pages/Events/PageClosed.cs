using CrestCore.Application;

namespace CrestCore.Contracts;

/// The engine's page is gone. Either the core asked the engine to close it,
/// having let the page go already or moved it to another engine, or the
/// engine closed it on its own authority, as an extension's
/// `chrome.tabs.remove` or `chrome.windows.remove` does. A page closed keeping
/// its state hands back what brings it back, when its engine can.
public sealed record PageClosed(Guid PageId, PageRestoreState? RestoreState) : PageEvent(PageId) {
    #region Actions - Pages

    /// What a page closed keeping its state hands back goes to its tab, though
    /// the core let the page go when it asked the engine to close it.
    internal override void Apply(Pages pages, Engine engine, PageTurn turn) {
        pages.KeepRestoreState(PageId, engine, RestoreState);
        base.Apply(pages, engine, turn);
    }

    /// A page the core still hosts closed on its engine's own authority, so
    /// what owns it closes, once: a repeated report finds the page closed.
    internal override void Apply(Pages pages, Page page, PageTurn turn) {
        if (!page.Phase.HoldsEnginePage) return;
        pages.Enter(page, PagePhase.Closed, turn.Changes);
        pages.CloseOwner(page, turn);
    }

    #endregion
}
