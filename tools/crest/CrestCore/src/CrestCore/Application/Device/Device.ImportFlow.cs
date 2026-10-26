using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The browser-import queue and review owned by this device.
internal sealed partial class Device {
    #region Variables

    private ImportFlowState? importFlow;
    internal ImportFlowState? ImportFlow => importFlow;

    #endregion

    #region Actions - Browser imports

    /// Runs one browser-import intent, publishing the flow it leaves.
    public void Handle(BrowserImportIntent intent, DeviceTurn turn) => intent.Apply(this, turn);

    /// Moves the import open on this device to the flow `revise` makes of it,
    /// over the session the import works on, and publishes it. Throws `Rejected`
    /// with `NoBrowserImport` when none is open.
    internal void ReviseFlow(ChangeFeed changes, Func<ImportFlowState, SessionState, ImportFlowState> revise) {
        var session = FlowSession();
        lock (gate) Publish(revise(importFlow ?? throw new Rejected(new NoBrowserImport()), session), changes);
    }

    /// The session the import works over, read outside the device lock.
    private SessionState FlowSession() {
        Guid workspaceId;
        lock (gate) workspaceId = (importFlow ?? throw new Rejected(new NoBrowserImport())).WorkspaceId;
        return (Attached(workspaceId) ?? throw new Rejected(new NoBrowserImport())).Current;
    }

    #endregion

    #region Actions - Steps

    /// `flow` when it is not reading or importing. Throws `Rejected` with
    /// `BrowserImportBusy` otherwise.
    internal static ImportFlowState Idle(ImportFlowState flow) => flow.Phase.IsBusy ? throw new Rejected(new BrowserImportBusy()) : flow;

    #endregion

    #region Actions - Reviews

    /// `flow` with its review edited by `edit`, while it is not importing.
    internal static ImportFlowState Editing(ImportFlowState flow, Func<ImportReview, ImportReview> edit) {
        var idle = Idle(flow);
        return idle.Review is { } review ? idle with { Review = edit(review) } : idle;
    }

    /// The review the import holds for `workspaceId`, which `ImportReviewedSpaces`
    /// imports, or null when there is none.
    public ImportReview? ImportReview(Guid workspaceId) {
        lock (gate) return importFlow is { } flow && flow.WorkspaceId == workspaceId ? flow.Review : null;
    }

    #endregion

    #region Actions - Publishing

    /// Publishes a changed import flow. The caller holds the device lock.
    internal void Publish(ImportFlowState flow, ChangeFeed changes) {
        if (ReferenceEquals(flow, importFlow)) return;
        importFlow = flow;
        changes.Publish(new ImportFlowChanged(importFlow));
    }

    #endregion
}
