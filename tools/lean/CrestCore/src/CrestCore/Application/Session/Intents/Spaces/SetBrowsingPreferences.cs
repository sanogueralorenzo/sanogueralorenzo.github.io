using CrestCore.Application;

namespace CrestCore.Contracts;

/// Sets how a Space blocks content and how long it keeps browsing records.
/// A Space whose retention changed is swept under the new rules in the same edit.
public sealed record SetBrowsingPreferences(Guid WorkspaceId, Guid SpaceId,
    ContentBlockingPolicy ContentBlocking, DataRetentionPreferences DataRetention)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Sets the Space's browsing preferences. A
    /// changed retention sweeps the Space under the new rules in
    /// the same edit, which then stages as the records it expired.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        var space = workspace.Editable(turn.Basis, SpaceId);
        var before = space.Settings.BrowsingPreferences;
        var preferences = before with {
            ContentBlocking = ContentBlocking,
            DataRetention = DataRetention
        };
        var configured = space.Configured(space.Settings with { BrowsingPreferences = preferences });
        if (before.DataRetention == preferences.DataRetention)
            return new(turn.Basis.Replacing(configured), SyncStaging.Edit);
        var swept = workspace.Expired(configured, turn.Now);
        bool unchanged = configured.Tabs.SequenceEqual(swept.Tabs) && configured.History.SequenceEqual(swept.History)
            && configured.ArchivedTabs.SequenceEqual(swept.ArchivedTabs);
        return new(turn.Basis.Replacing(swept),
            unchanged ? SyncStaging.Edit : SyncStaging.Expiry);
    }

    #endregion
}
