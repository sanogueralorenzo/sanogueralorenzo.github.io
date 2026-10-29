using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record RecordPageIcon(Guid WorkspaceId, Guid PageId, Guid SpaceId, Guid TabId, string Url,
    TabIconAccent? Accent, DateTimeOffset At) : Intent {
    internal override IReadOnlyList<Change> Route(CrestApp app) => app.RecordPage(WorkspaceId,
        new IconAdoption(PageId, SpaceId, At, TabId, new PageIcon(Url, Accent)));
}
