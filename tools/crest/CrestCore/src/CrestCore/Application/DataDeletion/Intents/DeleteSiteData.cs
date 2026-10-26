using CrestCore.Application;

namespace CrestCore.Contracts;

/// Erases what every engine keeps for profile `ProfileId` in `Categories` for
/// the site of each of `Hosts`: its cookies, storage and service workers, its
/// cache, or both. A site's history stays. An `Ephemeral` profile keeps its
/// data only in memory, while it is open, and its erasure touches nothing on
/// disk.
public sealed record DeleteSiteData(Guid RequestId, Guid ProfileId, bool Ephemeral, IReadOnlyList<string> Hosts,
    IReadOnlyList<BrowsingDataCategory> Categories) : DataDeletionIntent(RequestId) {
    #region Actions - Data deletion

    /// Refused with `InvalidSiteHost` for no host, or one that is blank or too
    /// long, and with `NoBrowsingDataCategory` for no category a site's data
    /// can be cleared by.
    internal override void Apply(DataDeletions deletions, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        var hosts = Hosts.Select(host => host.Trim().ToLowerInvariant()).Distinct().ToArray();
        if (hosts.Length == 0 || hosts.Any(host => host.Length is 0 or > DataDeletions.MaximumHostLength))
            throw new Rejected(new InvalidSiteHost());
        var categories = BrowsingDataCategory.All.Where(category => category.ClearsBySite && Categories.Contains(category)).ToArray();
        if (categories.Length == 0) throw new Rejected(new NoBrowsingDataCategory());
        deletions.Start(new(RequestId, profileId: null),
            erasure => new EraseSiteData(ProfileId, Ephemeral, hosts, categories, erasure), changes, issue);
    }

    #endregion

    #region Actions - Access

    /// Refused with `SpaceLocked` while a locked Space holds the profile.
    internal override void Guard(Device device) => device.RefuseLockedProfile(ProfileId);

    #endregion
}
