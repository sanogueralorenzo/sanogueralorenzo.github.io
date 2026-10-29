using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

public sealed record NavigateTab(Guid WorkspaceId, Guid SpaceId, Guid TabId, string Input) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Gives a tab that shows no web page the address the intent's input
    /// resolves to by its Space's rules, on an engine that shows internal
    /// pages when `allowsInternalPages`, titled by its host, so a page can open
    /// for it; see `NavigateTab`. A tab that already shows a web page is left
    /// as it is.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        var stored = space.Tabs.FirstOrDefault(tab => tab.Id == TabId) ?? throw new Rejected(new UnknownTab(TabId));
        var url = AddressResolution.Loading(Input, workspace.SearchProvider,
            allowsInternalPages: false);
        var tab = BrowserTab.Restore(stored);
        if (tab.Content.IsWebPage) return new(turn.Basis, SyncStaging.PageReport);
        var address = new Uri(url);
        tab.ObserveAppearance(url, address.Host.Length > 0 ? address.Host : url);
        var tabs = space.Tabs.Select(candidate => candidate.Id == TabId ? tab.State : candidate);
        return new(turn.Basis.Replacing(space with { Tabs = [.. tabs] }), SyncStaging.PageReport);
    }

    #endregion
}
