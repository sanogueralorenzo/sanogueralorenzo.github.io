using CrestCore.Application;

namespace CrestCore.Contracts;

/// Finishes setup from the window `WindowId`: applies the manual setup when
/// the person set Spaces up by hand, marks setup done on this device, and
/// publishes `SetupFinished` with the Space the Getting Started guide opens
/// in when the entry opens it.
///
/// Refused with `PersistentWorkspaceRequired` from a workspace setup cannot
/// change, `GuideSpaceLocked` while the Space the guide would open in is
/// locked, which the platform unlocks before finishing again, and whatever
/// refuses the manual setup.
public sealed record FinishSetup(Guid WindowId) : SetupFlowIntent {
    #region Actions - Device

    /// The manual setup is applied through the workspace as any import is,
    /// after the Space the guide would open in is found unlocked; then the
    /// device completes setup.
    internal override void Apply(Device device, DeviceTurn turn) {
        var finish = device.FinishingSetup();
        var authority = device.Workspace(finish.WorkspaceId);
        var apply = new ApplyManualSetup(finish.WorkspaceId, WindowId);
        if (finish.OpensGuide) {
            var proposed = finish.AppliesManualSetup ? authority.Preview(apply, turn.Now).Session : authority.Current;
            if (proposed.Spaces.FirstOrDefault() is { } first && authority.IsLocked(first))
                throw new Rejected(new GuideSpaceLocked(first.Id));
        }
        if (finish.AppliesManualSetup) {
            authority.Handle(apply, turn.Now, turn.Ids, turn.Pages);
            device.FinishManualSetup(finish.WorkspaceId, turn.Changes);
        }
        device.FinishedSetup(finish, finish.OpensGuide ? authority.Current.Spaces.FirstOrDefault()?.Id : null, turn.Changes);
    }

    #endregion
}
