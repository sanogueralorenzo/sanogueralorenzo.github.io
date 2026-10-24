using CrestCore.Application;

namespace CrestCore.Contracts;

/// The system asks for memory back at `Level`. The core unloads pages nobody
/// sees, off screen longest first, as many as the device's platform gives
/// back at that level. A page a window shows, one running media (playing,
/// capturing, or holding a Picture in Picture window, even paused), one
/// whose tab keeps its page loaded or an agent uses, and a Quick Window's or
/// Peek's page all stay.
public sealed record ReportMemoryPressure(MemoryPressureLevel Level) : PageIntent {
    #region Actions - Pages

    /// Unloads the pages memory pressure may take back: off screen, live on
    /// an engine that can bring them back, showing a document, owned by a tab
    /// that does not keep its page loaded and no agent uses, and running no
    /// media. A page that
    /// has shown no document yet stays: nothing of it could come back, and a
    /// popup waiting for its first document would lose the page that opened
    /// it. Each page unloaded closes keeping its state, which its tab keeps.
    internal override void Apply(Pages pages, PageTurn turn) {
        pages.Stamp(pages.Clock.Now, turn.Issue);
        var candidates = pages.All
            .Where(page => page.TabId is not null && page.Phase == PagePhase.Live && page.HiddenSince is not null
                && page.Live.Url is not null && page.Engine.Supports(EngineCapability.PageResidency) && !page.RunsMedia
                && pages.Tab(page) is { KeepsPageLoaded: false } && !pages.Device.HoldsForAgent(page.TabId.Value))
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
