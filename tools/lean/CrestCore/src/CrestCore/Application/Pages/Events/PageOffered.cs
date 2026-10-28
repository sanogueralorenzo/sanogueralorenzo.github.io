using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// The engine opened a page of its own in the profile `ProfileId` names: a
/// script's `window.open`, a link to a new window or tab, or an extension's
/// tab. The page stays on the engine that opened it, which is its opener's.
/// `SourcePageId` names the page that opened it, when one did. `SpaceId` names
/// the Space of a window the engine made for the page, as it does for a
/// window a page asked for with window features, a popup, and for one an
/// extension created; without a source, `WindowId` names the Crest window
/// whose engine window holds it. `Url` is where it is heading, and
/// `Foreground` whether the engine brought it to the front. The core adopts
/// it with `AdoptOfferedPage` or refuses it with `RejectOfferedPage`.
public sealed record PageOffered(Guid OfferId, Guid ProfileId, Guid? SourcePageId, Guid? WindowId, Guid? SpaceId, string Url,
    bool Foreground) : EngineEvent {
    #region Actions - Pages

    internal void Apply(Pages pages, Engine engine, PageTurn turn) {
        var source = SourcePageId is { } sourceId && pages.Hosted(sourceId) is { } opener
            && ReferenceEquals(opener.Engine, engine) && opener.ProfileId == ProfileId
                ? opener
                : null;
        if (!Adopted(pages, engine, source, turn)) turn.Issue(engine, new RejectOfferedPage(OfferId));
    }

    /// Opens the offered page's tab and gives the page to it, and answers
    /// whether a Space took it.
    private bool Adopted(Pages pages, Engine engine, Page? source, PageTurn turn) {
        Guid workspaceId, windowId, spaceId;
        Guid? afterTabId;
        if (source is not null) {
            (workspaceId, windowId, spaceId, afterTabId) = (source.WorkspaceId, source.WindowId, source.SpaceId, source.TabId);
        } else if (WindowId is { } holder && pages.Device.Showing(holder, SpaceId) is { } shown) {
            windowId = holder;
            (workspaceId, spaceId, afterTabId) = shown;
        } else {
            return false;
        }
        if (pages.Device.Attached(workspaceId) is not { } workspace || Hostable(workspace, spaceId) is not { } space
            || space.ProfileId != ProfileId)
            return false;
        var tabId = pages.Ids.Next();
        try {
            workspace.Handle(new OpenTab(workspaceId, windowId, space.Id, tabId,
                new TabContent(Url, View: null, Title: null), TabPlacement.Current, afterTabId, Foreground),
                pages.Clock.Now, pages.Ids, pages);
        } catch (Rejected) {
            // The Space's tabs are full, or the address is one no tab shows.
            return false;
        }
        // Every page the engine offers was opened by software, a page or an
        // extension, never by the person, so it may close itself as it would
        // in any browser, and it stays on the engine that opened it.
        var page = new Page(pages.Ids.Next(), engine, space.ProfileId, workspaceId, space.Id, tabId, windowId, transient: null,
            openedByPage: true);
        pages.Add(page);
        turn.Changes.Publish(new PageOpened(page.State));
        turn.Changes.Publish(new OfferedPageAdopted(page.Id, workspaceId, windowId, space.Id, tabId, Foreground));
        turn.Issue(engine, new AdoptOfferedPage(page.Id, OfferId, page.ProfileId, workspace.IsPrivateBrowsing, windowId));
        return true;
    }

    /// The Space a page may live in, as `Pages.Hosting` decides, or null where
    /// a rule refuses it.
    private static SpaceState? Hostable(NativeSessionAuthority workspace, Guid spaceId) =>
        workspace.Current.Spaces.FirstOrDefault(space => space.Id == spaceId) is { } space && !workspace.IsDeleting(spaceId)
            ? space
            : null;

    #endregion

    #region Actions - Routing

    internal override void Route(CrestApp app, Engine engine, ChangeFeed changes) {
        Apply(app.Pages, engine, new PageTurn(changes, app.Issue, app.ClosePreparations));
        app.AfterPageReport(changes);
    }

    #endregion
}
