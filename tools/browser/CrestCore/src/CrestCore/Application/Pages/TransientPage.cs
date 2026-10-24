namespace CrestCore.Application;

/// A Quick Window's or Peek's page as a session intent about it reads it: the
/// workspace and Space it lives in, the profile its engine page keeps, whether
/// its engine can move it to another window, so a tab can take it, and the
/// address and title it shows, or showed last when it is already gone.
internal sealed record TransientPage(Guid Id, Guid WorkspaceId, Guid SpaceId, Guid ProfileId, bool MovesBetweenWindows,
    string? Address, string Title);
