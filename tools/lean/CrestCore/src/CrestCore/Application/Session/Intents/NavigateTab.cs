using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

public sealed record NavigateTab(Guid WorkspaceId, Guid SpaceId, Guid TabId, string Url) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Gives a native tab the address the host resolved, so a page can open.
    /// An existing web page keeps its address until its page reports one.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        var stored = space.Tabs.FirstOrDefault(tab => tab.Id == TabId) ?? throw new Rejected(new UnknownTab(TabId));
        if (!Uri.TryCreate(Url, UriKind.Absolute, out var address)
            || (WebScheme.Named(address.Scheme) is null && address.Scheme != Uri.UriSchemeFile
                && Url != "about:blank" && !Url.StartsWith("about:blank#", StringComparison.Ordinal)))
            throw new Rejected(new UnsupportedAddress(Url));
        var tab = BrowserTab.Restore(stored);
        if (tab.Content.IsWebPage) return new(turn.Basis, SyncStaging.PageReport);
        tab.ObserveAppearance(Url, address.Host.Length > 0 ? address.Host : Url);
        var tabs = space.Tabs.Select(candidate => candidate.Id == TabId ? tab.State : candidate);
        return new(turn.Basis.Replacing(space with { Tabs = [.. tabs] }), SyncStaging.PageReport);
    }

    #endregion
}
