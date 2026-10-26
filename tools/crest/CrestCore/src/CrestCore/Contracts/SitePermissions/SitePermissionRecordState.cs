namespace CrestCore.Contracts;

/// One choice a Space keeps: a persistent answer for a capability at an
/// origin, narrowed by `Detail` or site-wide when it is null.
public sealed record SitePermissionRecordState(Guid Id, Guid SpaceId, SiteOrigin Origin, SitePermission Permission, string? Detail,
    SitePermissionDecision Decision) {
    #region Variables

    /// The origin as a person reads it.
    [Resolved]
    public string SiteName => Origin.DisplayName;

    #endregion
}
