namespace CrestCore.Contracts;

#region Rejections

/// The workspace borrows its one Space from the workspace that owns the
/// Space's profile, which changes the Space's settings and makes, orders and
/// deletes Spaces.
public sealed record BorrowedProfileRequiresOwner(Guid WorkspaceId) : Rejection;

/// Deleting the Space would leave the workspace without one.
public sealed record CannotDeleteLastSpace() : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Crest needs at least one Space.";

    #endregion
}

/// The order does not name each of the workspace's Spaces exactly once.
public sealed record InvalidSpaceOrder() : Rejection;

/// Only a private workspace starts over.
public sealed record NotPrivateWorkspace(Guid WorkspaceId) : Rejection;

/// The workspace already holds a Space with this identity.
public sealed record SpaceAlreadyExists(Guid SpaceId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "That Space already exists.";

    #endregion
}

/// The workspace already holds `Limit` Spaces, or would hold more.
public sealed record SpaceLimitReached(int Limit) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized(Argument = nameof(Limit))]
    public string Message => "Crest supports up to %lld Spaces.";

    #endregion
}

/// The Space's deletion is not the one the intent names: another operation
/// began it, or none did.
public sealed record WrongDeletionOperation(Guid SpaceId) : Rejection;

#endregion
