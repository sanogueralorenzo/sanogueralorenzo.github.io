using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Sets how a Space's sidebar and icon look, within the ranges every device
/// draws.
public sealed record SetSpaceBranding(Guid WorkspaceId, Guid SpaceId, SpaceBranding Branding) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        var branding = SpaceBranding.Normalized(Branding);
        return workspace.SettingSpace(turn.Basis, workspace.Editable(turn.Basis, SpaceId),
            settings => settings with { Branding = branding }, SyncStaging.Edit);
    }

    #endregion
}
