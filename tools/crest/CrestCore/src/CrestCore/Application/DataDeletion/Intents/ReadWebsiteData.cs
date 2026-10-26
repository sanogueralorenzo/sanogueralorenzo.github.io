using CrestCore.Application;

namespace CrestCore.Contracts;

/// Lists the sites that keep data in profile `ProfileId` on every engine, or
/// only `Host`'s own sites when it is given: the site it belongs to, and any
/// domain it is under that keeps data of its own. It ends with
/// `WebsiteDataRead` for `RequestId`. An `Ephemeral` profile keeps its data
/// only in memory. Refused with `SpaceLocked` while a locked Space holds the
/// profile, since its sites tell what the Space browsed, and with
/// `InvalidSiteHost` for a `Host` that is blank or too long.
public sealed record ReadWebsiteData(Guid RequestId, Guid ProfileId, bool Ephemeral, string? Host) : Intent {
    #region Actions - Routing

    internal override IReadOnlyList<Change> Route(CrestApp app) =>
        app.Turn(changes => {
            app.Device.RefuseLockedProfile(ProfileId);
            var host = Host is null ? null : SiteDataReads.SiteName(Host);
            if (host is { Length: 0 or > DataDeletions.MaximumHostLength }) throw new Rejected(new InvalidSiteHost());
            app.SiteDataReads.Start(RequestId, ProfileId, Ephemeral, host, app.Device, changes, app.Issue);
        });

    #endregion
}
