using CrestCore.Application;

namespace CrestCore.Contracts;

/// Erases what every engine keeps for profile `ProfileId` in `Categories`
/// that changed within `Range`, ending now: the sites' cookies and storage,
/// the cache, and the engine's own record of visits. What extensions store
/// stays. The Space's history, which the core keeps, is cleared by
/// `ClearHistory`. An `Ephemeral` profile keeps its data only in memory.
public sealed record DeleteBrowsingData(Guid RequestId, Guid ProfileId, bool Ephemeral, BrowsingDataRange Range,
    IReadOnlyList<BrowsingDataCategory> Categories) : DataDeletionIntent(RequestId) {
    #region Actions - Data deletion

    /// Refused with `NoBrowsingDataCategory` when no category is chosen.
    internal override void Apply(DataDeletions deletions, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        var categories = BrowsingDataCategory.All.Where(Categories.Contains).ToArray();
        if (categories.Length == 0) throw new Rejected(new NoBrowsingDataCategory());
        var since = Range.Since(deletions.Clock.Now);
        deletions.Start(new(RequestId, profileId: null),
            erasure => new EraseBrowsingData(ProfileId, Ephemeral, since, categories, erasure), changes, issue);
    }

    #endregion

    #region Actions - Access

    /// Refused with `SpaceLocked` while a locked Space holds the profile.
    internal override void Guard(Device device) => device.RefuseLockedProfile(ProfileId);

    #endregion
}
