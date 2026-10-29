using CrestCore.Application;

namespace CrestCore.Contracts;

/// Records native page facts atomically in the session. Renderer state and
/// duplicate-finish detection belong to the native page owner.
public sealed record RecordPageNavigation(Guid WorkspaceId, Guid PageId, Guid SpaceId, Guid? TabId, string Url,
    string Title, DateTimeOffset At, Guid VisitId, bool HasIcon, TabIconAccent? IconAccent) : Intent {
    internal override IReadOnlyList<Change> Route(CrestApp app) => app.RecordPage(WorkspaceId,
        new NavigationRecord(PageId, SpaceId, At, TabId, Url, Title, HasIcon ? new PageIcon(Url, IconAccent) : null, VisitId));
}
