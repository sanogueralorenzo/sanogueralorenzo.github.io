using CrestCore.Application;

namespace CrestCore.Contracts;

/// Applies the manual setup this device holds for the workspace: each new
/// Space of the setup joins with its identity, profile, name and look, and
/// each existing Space takes the name and look the setup gave it. When the
/// setup's order was edited, the Spaces take it, followed by any Space the
/// setup does not name. A first launch's Spaces stop being disposable. The
/// setup ends once it is applied.
///
/// Refused with `NoManualSetup` when no setup is in progress for the
/// workspace, `SpaceProfileChanged` when an existing Space no longer uses the
/// setup's profile, and `SpaceAlreadyExists` or `ProfileInUse` when a new
/// Space takes an identity or profile another Space holds.
public sealed record ApplyManualSetup(Guid WorkspaceId, Guid WindowId) : ImportWorkspace(WorkspaceId, WindowId) {
    #region Actions - Session

    /// Applies the manual setup the device holds for this workspace; see
    /// `ApplyManualSetup`. The device ends the setup once the session accepts it.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        if (!workspace.Kind.KeepsAppPreferences) throw new Rejected(new PersistentWorkspaceRequired(workspace.WorkspaceId));
        var setup = workspace.Device?.ManualSetup(workspace.WorkspaceId) ?? throw new Rejected(new NoManualSetup());
        return workspace.Importing(turn.Basis, this, [.. setup.Spaces.Select(NativeWorkspaceImport.SetupSpace)], turn.Previewed, turn.Now,
            turn.Ids,
            import => import.ApplySetup(setup));
    }

    #endregion

    #region Actions - Routing

    /// An applied manual setup ends.
    internal override void Commit(CrestApp app, ChangeFeed changes) {
        base.Commit(app, changes);
        app.Device.FinishManualSetup(WorkspaceId, changes);
    }

    #endregion
}
