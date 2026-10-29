namespace CrestCore.Contracts;

/// A Space removal cannot commit until the native owner erased its profile in this run.
public sealed record SpaceDataNotErased(Guid SpaceId) : Rejection;
