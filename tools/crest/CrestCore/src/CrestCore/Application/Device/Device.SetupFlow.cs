using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Setup on this device: the flow the person is in, over one workspace, and
/// whether this device has completed setup, which the device store keeps. The
/// flow holds the browsers chosen to import from, the queue of them and the
/// review of the one it is on; the platform reads each browser and imports its
/// passwords, and tells the flow how that went. `FinishSetup` applies the
/// manual setup and completes setup; see `CrestApp`.
internal sealed partial class Device {
    #region Types

    /// What finishing setup over `WorkspaceId` does: apply the manual setup the
    /// device holds, and open the Getting Started guide.
    public sealed record SetupFinish(Guid WorkspaceId, bool AppliesManualSetup, bool OpensGuide, int CreatedSpaces);

    #endregion

    #region Variables

    /// Setup as the person sees it, or null while it is not open.
    private SetupFlowState? setupFlow;
    internal SetupFlowState? SetupFlow => setupFlow;
    /// Whether this device has completed setup.
    private bool setupCompleted;
    internal bool SetupCompleted { get => setupCompleted; set => setupCompleted = value; }

    #endregion

    #region Actions - Setup flow intents

    /// Runs one setup flow intent, publishing the flow it leaves.
    public void Handle(SetupFlowIntent intent, DeviceTurn turn) => intent.Apply(this, turn);

    /// Moves the setup open on this device to the flow `revise` makes of it,
    /// over the session setup works on, and publishes it. Throws `Rejected`
    /// with `NoSetup` when none is open.
    internal void ReviseFlow(ChangeFeed changes, Func<SetupFlowState, SessionState, SetupFlowState> revise) {
        var session = FlowSession();
        lock (gate) Publish(revise(setupFlow ?? throw new Rejected(new NoSetup()), session), changes);
    }

    /// The session setup works over, read outside the device lock.
    private SessionState FlowSession() {
        Guid workspaceId;
        lock (gate) workspaceId = (setupFlow ?? throw new Rejected(new NoSetup())).WorkspaceId;
        return (Attached(workspaceId) ?? throw new Rejected(new NoSetup())).Current;
    }

    #endregion

    #region Actions - Steps

    /// `flow` when it is not reading or importing. Throws `Rejected` with
    /// `SetupBusy` otherwise.
    internal static SetupFlowState Idle(SetupFlowState flow) => flow.Phase.IsBusy ? throw new Rejected(new SetupBusy()) : flow;

    #endregion

    #region Actions - Reviews

    /// `flow` with its review edited by `edit`, while it is not importing.
    internal static SetupFlowState Editing(SetupFlowState flow, Func<SetupImportReview, SetupImportReview> edit) {
        var idle = Idle(flow);
        return idle.Review is { } review ? idle with { Review = edit(review) } : idle;
    }

    /// The review setup holds for `workspaceId`, which `ImportReviewedSpaces`
    /// imports, or null when there is none.
    public SetupImportReview? ImportReview(Guid workspaceId) {
        lock (gate) return setupFlow is { } flow && flow.WorkspaceId == workspaceId ? flow.Review : null;
    }

    #endregion

    #region Actions - Finishing

    /// What finishing the setup open on this device does. Throws `Rejected`
    /// with `NoSetup` when none is open, `SetupBusy` while it reads or imports,
    /// and `PersistentWorkspaceRequired` over a workspace setup cannot change.
    public SetupFinish FinishingSetup() {
        SetupFlowState flow;
        lock (gate) flow = Idle(setupFlow ?? throw new Rejected(new NoSetup()));
        var authority = Attached(flow.WorkspaceId) ?? throw new Rejected(new NoSetup());
        if (!authority.Kind.KeepsAppPreferences) throw new Rejected(new PersistentWorkspaceRequired(flow.WorkspaceId));
        lock (gate) {
            var draft = flow.Step.AppliesManualSetup && setupDraft?.WorkspaceId == flow.WorkspaceId ? setupDraft : null;
            return new(flow.WorkspaceId, draft is not null, flow.Entry.OpensGuide(setupCompleted), draft?.Spaces.Count(space => space.IsNew) ?? 0);
        }
    }

    /// Setup finished as `finish` said: this device has completed setup, no
    /// launch gate holds for the rest of this run, the flow shows what it did,
    /// and the platform opens the guide in `guideSpaceId` when it names one.
    public void FinishedSetup(SetupFinish finish, Guid? guideSpaceId, ChangeFeed changes) {
        ArgumentNullException.ThrowIfNull(finish);
        ArgumentNullException.ThrowIfNull(changes);
        lock (gate) {
            setupFinishedThisRun = true;
            if (!setupCompleted) {
                setupCompleted = true;
                storage?.EnqueueDevice(Records());
                changes.Publish(new SetupCompletedChanged(true));
            }
            if (setupFlow is { } flow)
                Publish(flow with {
                    Step = SetupStep.Complete,
                    Phase = SetupPhase.Idle,
                    Summary = finish.AppliesManualSetup ? new SetupSummary(IsImport: false, 0, 0, finish.CreatedSpaces) : flow.Summary
                }, changes);
            changes.Publish(new SetupFinished(finish.WorkspaceId, guideSpaceId));
        }
    }

    #endregion

    #region Actions - Publishing

    /// Holds `flow` with where Back and Next lead from its step and what
    /// finishing opens, and publishes it. The flow setup already holds, which
    /// an intent that changed nothing answers, is not published again. The
    /// caller holds the device lock.
    internal void Publish(SetupFlowState flow, ChangeFeed changes) {
        if (ReferenceEquals(flow, setupFlow)) return;
        bool opensGuide = flow.Entry.OpensGuide(setupCompleted);
        setupFlow = flow with {
            BackStep = flow.Step.Back(flow.Entry, platform),
            NextStep = flow.Step.Next(platform),
            OpensGuide = opensGuide,
            OpensCrestFromWelcome = setupCompleted && !opensGuide
        };
        changes.Publish(new SetupFlowChanged(setupFlow));
    }

    #endregion
}
