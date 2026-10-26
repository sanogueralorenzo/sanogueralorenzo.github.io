using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record RehostPage(Guid PageId, EngineKind Engine) : PageIntent {
    #region Actions - Pages

    internal override void Apply(Pages pages, PageTurn turn) {
        var page = pages.Known(PageId);
        pages.Hosting(pages.Device.Workspace(page.WorkspaceId), page.SpaceId);
        var engine = pages.Engines.Registered(Engine) ?? throw new Rejected(new UnregisteredEngine(Engine));
        if (!ReferenceEquals(engine, page.Engine))
            turn.Closing.Move(page, engine, page.Live.Address, RehostReason.PersonAsked, turn);
    }

    #endregion
}
