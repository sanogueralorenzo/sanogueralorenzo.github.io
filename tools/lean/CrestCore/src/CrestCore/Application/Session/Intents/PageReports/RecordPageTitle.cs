using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record RecordPageTitle(Guid WorkspaceId, Guid PageId, Guid SpaceId, Guid? TabId, string Url,
    string Title, DateTimeOffset At, bool Visit) : Intent {
    internal override IReadOnlyList<Change> Route(CrestApp app) => app.RecordPage(WorkspaceId,
        new TitleRecord(PageId, SpaceId, At, TabId, Url, Title, Visit));
}
