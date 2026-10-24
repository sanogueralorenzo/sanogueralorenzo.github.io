namespace CrestCore.Contracts;

#region Rejections

/// The Quick Window's or Peek's page was already kept as a tab or archived,
/// so it is not kept again.
public sealed record TransientAlreadyCompleted(Guid PageId) : Rejection;

#endregion
