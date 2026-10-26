using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The manual setup this device holds: the one in progress over a workspace,
/// which follows that workspace's Spaces, and on a platform that keeps an
/// unfinished setup, the copy the device store keeps for the next launch.
/// `ApplyManualSetup` reads the one in progress and ends it once applied.
internal sealed partial class Device {
    #region Variables

    /// The setup in progress, or null.
    private SetupDraft? setupDraft;
    /// What the device store keeps of an unfinished setup, which setup goes
    /// on with at its manual-setup step. Always null on a platform that keeps none.
    private KeptSetupDraft? keptSetupDraft;
    internal KeptSetupDraft? KeptSetupDraft { get => keptSetupDraft; set => keptSetupDraft = value; }

    #endregion

    #region Actions - Setup intents

    /// Runs one setup intent, publishing the setup it leaves.
    public void Handle(SetupDraftIntent intent, DeviceTurn turn) => intent.Apply(this, turn);

    /// Keeps the setup `revise` makes of the one in progress, and publishes it.
    /// Throws `Rejected` with `NoManualSetup` when none is in progress.
    internal void ReviseSetup(ChangeFeed changes, Func<SetupDraft, SetupDraft> revise) {
        lock (gate) KeepSetup(revise(setupDraft ?? throw new Rejected(new NoManualSetup())), changes);
    }

    /// Starts a setup of `session`'s Spaces over `workspaceId` in `look`, or
    /// goes on with the one held or kept unless `startsOver`, and publishes
    /// it. The caller holds the device lock.
    internal void BeginSetup(Guid workspaceId, SessionState session, bool startsOver, SetupLook look, ChangeFeed changes,
        IIdSource ids) {
        var resumed = startsOver ? null
            : setupDraft is { } held && held.WorkspaceId == workspaceId ? held
            : keptSetupDraft?.For(workspaceId);
        var draft = resumed is null ? SetupDraft.Started(workspaceId, session, ids.Next, look) : resumed.Reconciled(session);
        KeepSetup(draft, changes: null);
        changes.Publish(new SetupDraftChanged(draft));
    }

    /// Gives the setup held over `workspaceId`, when there is one, `look` in
    /// place of `previous` for the Spaces it makes, and publishes it. The
    /// caller holds the device lock.
    internal void RestyleSetup(Guid workspaceId, SessionState session, SetupLook previous, SetupLook look, ChangeFeed changes) {
        if (setupDraft is not { } draft || draft.WorkspaceId != workspaceId) return;
        KeepSetup(draft.Restyled(previous, look, session), changes);
    }

    /// The look the Spaces setup makes wear: the one setup chose, or Crest's
    /// own while setup is not open. The caller holds the device lock.
    internal SetupLook SetupLook => setupFlow?.Look ?? SetupLook.Heraldic;

    #endregion

    #region Actions - Applying

    /// The setup in progress over `workspaceId`, which `ApplyManualSetup`
    /// applies, or null when there is none.
    public SetupDraft? ManualSetup(Guid workspaceId) {
        lock (gate) return setupDraft is { } draft && draft.WorkspaceId == workspaceId ? draft : null;
    }

    /// The setup over `workspaceId` was applied: it ends.
    public void FinishManualSetup(Guid workspaceId, ChangeFeed changes) {
        ArgumentNullException.ThrowIfNull(changes);
        lock (gate) {
            if (setupDraft?.WorkspaceId == workspaceId) KeepSetup(null, changes);
        }
    }

    /// The setup in progress over `workspaceId` following its Spaces as
    /// `next` holds them, answering the change to publish when it changed.
    /// The caller holds the device lock.
    private SetupDraftChanged? FollowingSpaces(Guid workspaceId, SessionState next) {
        if (setupDraft is not { } draft || draft.WorkspaceId != workspaceId) return null;
        var followed = draft.Reconciled(next);
        if (ReferenceEquals(followed, draft)) return null;
        KeepSetup(followed, changes: null);
        return new(followed);
    }

    #endregion

    #region Actions - Keeping

    /// Holds `draft` as the setup in progress, and keeps it for the next
    /// launch on a platform that keeps one, publishing it into `changes` when
    /// it changed. The caller holds the device lock.
    internal void KeepSetup(SetupDraft? draft, ChangeFeed? changes) {
        bool changed = !ReferenceEquals(draft, setupDraft);
        setupDraft = draft;
        var kept = platform.KeepsSetupDraft && draft is not null ? KeptSetupDraft.From(draft) : null;
        if (!KeptSetupDraft.Same(kept, keptSetupDraft)) {
            keptSetupDraft = kept;
            storage?.EnqueueDevice(Records());
        }
        if (changed) changes?.Publish(new SetupDraftChanged(draft));
    }

    #endregion
}
