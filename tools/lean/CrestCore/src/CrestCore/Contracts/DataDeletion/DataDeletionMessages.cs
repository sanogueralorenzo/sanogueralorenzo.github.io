namespace CrestCore.Contracts;

#region Changes

/// A data deletion ended: `Deleted` says every registered engine erased what
/// it was asked to.
public sealed record DataDeleted(Guid RequestId, bool Deleted) : Change;

/// The sites that keep data in a profile, merged across every registered
/// engine and sorted by name. `Complete` says every engine listed its own; a
/// site an engine could not list may be missing.
public sealed record WebsiteDataRead(Guid RequestId, IReadOnlyList<StoredSite> Sites, bool Complete) : Change;

#endregion

#region Rejections

/// A site data deletion named no host a site can have.
public sealed record InvalidSiteHost : Rejection;

/// A browsing data deletion chose nothing to clear, or for a site, nothing
/// one site's share of can be cleared.
public sealed record NoBrowsingDataCategory : Rejection;

/// A Space's deletion cannot finish before this run erased its profile's data
/// on every registered engine.
public sealed record SpaceDataNotErased(Guid SpaceId) : Rejection;

#endregion
