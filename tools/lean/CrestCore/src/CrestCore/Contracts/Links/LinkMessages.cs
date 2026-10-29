namespace CrestCore.Contracts;

/// The regular window/Space an external link, document or system sign-in uses.
public sealed record ExternalOpenPlacement(Guid? WindowId, Guid? SpaceId, bool OpensWindow);
