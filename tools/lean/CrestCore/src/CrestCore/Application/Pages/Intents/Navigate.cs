using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

public sealed record Navigate(Guid PageId, string Input) : PageIntent {
    #region Actions - Pages

    internal override void Apply(Pages pages, PageTurn turn) =>
        Load(pages, turn, PageId, (provider, showsInternalPages) => AddressResolution.Loading(Input, provider, showsInternalPages));

    /// Loads into page `pageId` the address `resolve` makes with the global search
    /// engine and whether its current rendering engine shows internal pages.
    internal static void Load(Pages pages, PageTurn turn, Guid pageId, Func<SearchProvider, bool, string> resolve) {
        var page = pages.Known(pageId);
        if (!page.Phase.HoldsEnginePage) throw new Rejected(new PageNotLoadable(page.Id));
        _ = pages.Hosting(pages.Device.Workspace(page.WorkspaceId), page.SpaceId);
        var url = resolve(pages.Device.SearchProvider,
            page.Engine.Supports(EngineCapability.InternalPages));
        pages.Update(page, turn.Changes, () => page.Load(url));
        turn.Issue(page.Engine, new LoadPage(page.Id, url));
    }

    #endregion
}
