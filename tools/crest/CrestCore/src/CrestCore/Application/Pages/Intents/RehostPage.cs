using CrestCore.Application;

namespace CrestCore.Contracts;

/// Asks to move a page to `Engine`, honoring its before-unload decision.
/// `RemembersSite` records the site choice only when the move is accepted.
/// The core then closes the page on its engine, which hands back the history
/// it held, creates it on `Engine` in the same profile and window, and once
/// that engine has created it, loads the address the page showed. The page
/// keeps its identity, its owner, its window and its history, whose entries
/// return to the engine that held them when the person goes back or forward
/// to them; form state and the document stay behind. A page already on
/// `Engine` stays. Refused when the page is not open, its Space is locked or
/// being deleted, or this device did not register `Engine`.
public sealed record RehostPage(Guid PageId, EngineKind Engine, bool RemembersSite = false) : PageIntent {
    #region Actions - Pages

    internal override void Apply(Pages pages, PageTurn turn) {
        var page = pages.Known(PageId);
        pages.Hosting(pages.Device.Workspace(page.WorkspaceId), page.SpaceId);
        var engine = pages.Engines.Registered(Engine) ?? throw new Rejected(new UnregisteredEngine(Engine));
        if (!ReferenceEquals(engine, page.Engine))
            turn.Closing.Move(page, engine, page.Live.Address, RehostReason.PersonAsked, RemembersSite, turn);
        else if (RemembersSite && page.Live.Address is { } address && new WebAddress(address).Origin is { } origin)
            pages.Device.Choose(page.SpaceId, origin, engine.Kind);
    }

    #endregion
}
