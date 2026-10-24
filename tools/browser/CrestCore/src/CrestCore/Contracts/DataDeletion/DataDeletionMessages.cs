namespace CrestCore.Contracts;

#region Changes

/// A data deletion ended: `Deleted` says every registered engine erased what
/// it was asked to.
public sealed record DataDeleted(Guid RequestId, bool Deleted) : Change;

#endregion

#region Rejections

/// A site data deletion named no host a site can have.
public sealed record InvalidSiteHost : Rejection;

/// A Space's deletion cannot finish before this run erased its profile's data
/// on every registered engine.
public sealed record SpaceDataNotErased(Guid SpaceId) : Rejection;

#endregion
