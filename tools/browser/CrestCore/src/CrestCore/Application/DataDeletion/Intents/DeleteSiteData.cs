using CrestCore.Application;

namespace CrestCore.Contracts;

/// Erases the cookies, storage and caches of the site at `Host` that every
/// engine keeps for profile `ProfileId`. An `Ephemeral` profile keeps them
/// only in memory, while it is open.
public sealed record DeleteSiteData(Guid RequestId, Guid ProfileId, bool Ephemeral, string Host) : DataDeletionIntent(RequestId) {
    #region Actions - Data deletion

    /// Refused with `InvalidSiteHost` for a host that is blank or too long.
    internal override void Apply(DataDeletions deletions, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        if (Host.Trim() is not { Length: > 0 and <= DataDeletions.MaximumHostLength } host) throw new Rejected(new InvalidSiteHost());
        deletions.Start(new(RequestId, profileId: null),
            erasure => new EraseSiteData(ProfileId, Ephemeral, host.ToLowerInvariant(), erasure), changes, issue);
    }

    #endregion
}
