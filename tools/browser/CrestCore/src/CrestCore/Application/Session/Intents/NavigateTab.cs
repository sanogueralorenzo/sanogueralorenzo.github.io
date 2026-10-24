using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Gives a tab that shows a native view or the Start Page the web address
/// `Input` names, resolved by its Space's address rules as `Navigate` resolves
/// one and titled by its host, so a page can open for it and load there. A
/// tab that already shows a web page keeps its address until its engine
/// reports where the navigation landed, so the intent changes nothing for it.
/// Refused when the workspace, Space or tab is not there, the Space is locked
/// or being deleted, or `Input` names nothing a page can load, as blank input
/// does.
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
        var url = AddressResolution.Loading(Input, workspace.SearchCatalog.For(space.Settings.BrowsingPreferences, workspace.Kind.IsPrivate),
            turn.Pages?.OpensInternalPages ?? false);
        var tab = BrowserTab.Restore(stored);
        if (tab.Content.IsWebPage) return new(turn.Basis, SyncStaging.PageReport);
        var address = new Uri(url);
        tab.ObserveAppearance(url, address.Host.Length > 0 ? address.Host : url);
        var tabs = space.Tabs.Select(candidate => candidate.Id == TabId ? tab.State : candidate);
        return new(NativeSessionAuthority.Replacing(turn.Basis, space with { Tabs = [.. tabs] }), SyncStaging.PageReport);
    }

    #endregion
}
