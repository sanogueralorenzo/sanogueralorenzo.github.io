using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record ReportMemoryPressure(MemoryPressureLevel Level) : PageIntent {
    #region Actions - Pages

    /// Unloads the pages memory pressure may take back: off screen, live on
    /// an engine that can bring them back, showing a document, owned by a tab
    /// that no agent uses, and running no media. A page that
    /// has shown no document yet stays: nothing of it could come back, and a
    /// popup waiting for its first document would lose the page that opened
    /// it. Each page unloaded closes keeping its state, which its tab keeps.
    internal override void Apply(Pages pages, PageTurn turn) {
        pages.Stamp(pages.Clock.Now, turn.Issue);
        var candidates = pages.All
            .Where(page => page.TabId is not null && page.Phase == PagePhase.Live && page.HiddenSince is not null
                && page.Live.Url is not null && page.Engine.Supports(EngineCapability.PageResidency) && !page.RunsMedia
                && pages.Tab(page) is not null && !pages.Device.HoldsForAgent(page.TabId.Value))
            .OrderBy(page => page.HiddenSince).ThenBy(page => page.Id)
            .ToArray();
        foreach (var page in candidates.Take(pages.Device.Platform.ReleaseLimit(Level, candidates.Length))) {
            pages.Remove(page.Id);
            turn.Changes.Publish(new PageRemoved(page.Id));
            turn.Changes.Publish(new PageUnloaded(page.Id, page.WorkspaceId, page.TabId!.Value));
            pages.Close(page, keepsState: true, turn.Issue);
        }
    }

    #endregion
}
