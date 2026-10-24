using CrestCore.Contracts;

namespace CrestCore.Domain;

/// One persistent choice. `Detail` narrows a capability a site can ask for
/// more than one way, such as the URL scheme behind one external-app
/// hand-off; null is the site-wide rule. `ModifiedAt` is seconds since
/// 2001-01-01, the epoch every release stored, and is kept exactly as given.
public sealed record SitePermissionRecord(Guid Id, Guid Space, SiteOrigin Origin, SitePermission Permission,
    string? Detail, SitePermissionDecision Decision, double ModifiedAt) {
    #region Variables

    /// The record as the platform reads it.
    public SitePermissionRecordState State => new(Id, Space, Origin, Permission, Detail, Decision);

    #endregion
}
