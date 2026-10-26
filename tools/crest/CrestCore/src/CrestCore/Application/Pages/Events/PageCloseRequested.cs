using CrestCore.Application;

namespace CrestCore.Contracts;

/// A page's own script asked to close its window, as `window.close()` does,
/// once its document agreed to go. The engine keeps the page, and the core
/// decides the same way whichever engine asked: a page another page or an
/// extension opened closes what owns it, as the person closing it would, and
/// any other page stays. A tab the person opened or saved is never a site's to close, even
/// when its history holds one page.
public sealed record PageCloseRequested(Guid PageId) : PageEvent(PageId) {
    #region Actions - Pages

    /// A live page another page opened closes its owner; any other request
    /// changes nothing.
    internal override void Apply(Pages pages, Page page, PageTurn turn) {
        if (page.Phase == PagePhase.Live && page.OpenedByPage) pages.CloseOwner(page, turn);
    }

    #endregion
}
