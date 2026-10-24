namespace CrestCore.Contracts;

#region Rejections

/// The tab would cross between private browsing and other browsing, which
/// share nothing.
public sealed record PrivateWorkspaceBoundary(Guid DestinationWorkspaceId) : Rejection;

/// Neither workspace borrows the other's Spaces, and they borrow from no
/// workspace in common, so no tab moves between them.
public sealed record UnrelatedWorkspaces(Guid DestinationWorkspaceId) : Rejection;

#endregion
