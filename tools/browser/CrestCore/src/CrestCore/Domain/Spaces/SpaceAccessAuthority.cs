using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Process-local grants for exact Space and profile identities. The platform
/// owns the authentication prompt; only the result of the request still
/// pending can grant access. Callers serialize access. Nothing in this
/// authority is saved or synced.
public sealed class SpaceAccessAuthority {
    #region Variables

    private readonly HashSet<SpaceAccessAssignment> unlocked = [];
    private (Guid Request, SpaceAccessAssignment Assignment)? pending;

    #endregion

    #region Actions - Space access

    public bool IsLocked(SpaceAccessAssignment assignment, bool requiresAuthentication) =>
        requiresAuthentication && !unlocked.Contains(assignment);

    /// Whether this process holds the grant for `assignment`.
    public bool IsUnlocked(SpaceAccessAssignment assignment) => unlocked.Contains(assignment);

    /// Whether a request to unlock `assignment` is waiting.
    public bool IsAuthenticating(SpaceAccessAssignment assignment) => pending?.Assignment == assignment;

    /// Makes `request` the one waiting to unlock `assignment`, and answers the
    /// assignments whose access changed: none when the Space needs no
    /// authentication. Throws `Rejected` with `AuthenticationBusy` while
    /// another request is waiting.
    public IReadOnlyList<SpaceAccessAssignment> Begin(SpaceAccessAssignment assignment, bool requiresAuthentication, Guid request) {
        if (!IsLocked(assignment, requiresAuthentication)) return [];
        if (pending is not null) throw new Rejected(new AuthenticationBusy());
        pending = (request, assignment);
        return [assignment];
    }

    /// Ends the waiting request `request` for `space`, granting its profile
    /// when the device owner authenticated. Throws `Rejected` with
    /// `StaleUnlockRequest` for any other request, which cannot consume the
    /// one waiting.
    public IReadOnlyList<SpaceAccessAssignment> Finish(Guid space, Guid request, bool authenticated) {
        if (pending is not { } current || current.Request != request || current.Assignment.Space != space)
            throw new Rejected(new StaleUnlockRequest(request));
        pending = null;
        if (authenticated) unlocked.Add(current.Assignment);
        return [current.Assignment];
    }

    /// Explicit locking always revokes: every grant for `space`, and the
    /// request waiting for it.
    public IReadOnlyList<SpaceAccessAssignment> Lock(Guid space) {
        var revoked = unlocked.Where(assignment => assignment.Space == space).ToList();
        unlocked.ExceptWith(revoked);
        if (pending?.Assignment is { } waiting && waiting.Space == space) {
            pending = null;
            if (!revoked.Contains(waiting)) revoked.Add(waiting);
        }
        return revoked;
    }

    /// Revokes every grant and cancels the waiting request. A scene the
    /// system's authentication prompt made inactive locks nothing while that
    /// request waits.
    public IReadOnlyList<SpaceAccessAssignment> LockAll(bool sceneWentInactive) {
        if (sceneWentInactive && pending is not null) return [];
        var revoked = unlocked.ToList();
        if (pending?.Assignment is { } waiting && !revoked.Contains(waiting)) revoked.Add(waiting);
        pending = null;
        unlocked.Clear();
        return revoked;
    }

    #endregion
}
