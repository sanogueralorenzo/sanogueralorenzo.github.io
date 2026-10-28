using CrestCore.Application;

namespace CrestCore.Contracts;

/// An extension grouped pages of the engine window that the Crest window
/// `WindowId` hosts as the tab group `GroupId`, or changed the group: its
/// title, color or collapsed state, or which pages it holds, which `PageIds`
/// lists in the engine's order. An empty list means the extension took the
/// last page out, which closed the group. The engine reports only what it
/// changed itself, never what a `GroupPages` command asked for, and never a
/// page leaving the group because its tab closed or moved to another window,
/// or its page was put away.
public sealed record PageGroupChanged(Guid GroupId, Guid WindowId, string Title, TabGroupColor Color, bool IsCollapsed,
    IReadOnlyList<Guid> PageIds) : EngineEvent {
    #region Actions - Pages

    /// The group's folder follows it; see `PageGroup.Show`. A group the core
    /// does not follow yet belongs to the Space of its first page that a tab
    /// owns, or of its first page, and the device store keeps it when that
    /// Space is the persistent session's.
    internal void Apply(Pages pages, Engine engine) {
        if (pages.Group(GroupId) is not { } group) {
            if (PageIds.Select(pages.Hosted).OfType<Page>().Where(page => ReferenceEquals(page.Engine, engine))
                .OrderBy(page => page.TabId is null).FirstOrDefault() is not { } first)
                return;
            group = new PageGroup(GroupId, engine.Kind, first.WorkspaceId, first.SpaceId,
                persists: pages.Device.Persistent()?.WorkspaceId == first.WorkspaceId);
            pages.Follow(group);
        } else if (group.Engine != engine.Kind) {
            return;
        }
        group.Show(this, pages);
    }

    #endregion

    #region Actions - Routing

    internal override void Route(CrestApp app, Engine engine, ChangeFeed changes) {
        Apply(app.Pages, engine);
        app.AfterPageReport(changes);
    }

    #endregion
}
