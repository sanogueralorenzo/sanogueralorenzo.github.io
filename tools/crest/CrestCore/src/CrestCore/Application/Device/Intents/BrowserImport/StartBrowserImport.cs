using CrestCore.Application;

namespace CrestCore.Contracts;

/// Starts an import into a persistent workspace when requested from Settings.
public sealed record StartBrowserImport(Guid WorkspaceId) : BrowserImportIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) {
        device.Workspace(WorkspaceId).RequirePreferenceOwner();
        lock (device.Gate) {
            if (device.ImportFlow is { Phase.IsBusy: true }) throw new Rejected(new BrowserImportBusy());
            device.Publish(new ImportFlowState(WorkspaceId, ImportStep.ImportBrowser, ImportPhase.Idle,
                Offered: [], Selected: [], Queue: null, Source: null, Review: null, Failure: null, Summary: null), turn.Changes);
        }
    }

    #endregion
}
