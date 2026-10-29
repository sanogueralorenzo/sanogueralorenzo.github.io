namespace CrestCore.Contracts;

/// A navigation accepted by the session, after its tab/history edits.
public sealed record NavigationRecorded(Guid PageId, Guid WorkspaceId, Guid SpaceId, Guid? TabId, string Url) : Change;

/// The Space is being deleted, so nothing new may live in its profile.
public sealed record SpaceBeingDeleted(Guid SpaceId) : Rejection {
    [Localized]
    public string Message => "That Space is being deleted.";
}

public sealed record UnknownSpace(Guid SpaceId) : Rejection;
