using CrestCore.Application;

namespace CrestCore.Contracts;

/// Expands or collapses a Space's saved tabs, stamping when that changed so
/// the newest choice wins across devices.
public sealed record ExpandSavedTabs(Guid WorkspaceId, Guid SpaceId, bool IsExpanded) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        var space = workspace.Editable(turn.Basis, SpaceId);
        return space.Settings.IsSavedTabsExpanded == IsExpanded ? new(turn.Basis, SyncStaging.Edit)
            : workspace.SettingSpace(turn.Basis, space,
                settings => settings with { IsSavedTabsExpanded = IsExpanded, SavedTabsExpansionModifiedAt = turn.Now },
                SyncStaging.Edit);
    }

    #endregion
}
