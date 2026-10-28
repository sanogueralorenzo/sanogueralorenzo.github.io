namespace CrestCore.Contracts;

#region Rejections

/// The Space keeps no archived tab to reopen.
public sealed record NoArchivedTabs(Guid SpaceId) : Rejection;

/// The Space's archive holds no tab with this identity.
public sealed record UnknownArchivedTab(Guid TabId) : Rejection;

#endregion
