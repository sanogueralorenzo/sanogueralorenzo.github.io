using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Variables

    private SpaceAccessAuthority? access;

    /// Sync materialization consults the same grants the command gate uses, so
    /// an incoming record cannot remove protection this device never unlocked.
    internal SpaceAccessAuthority? Access { get { lock (Gate) return access; } }

    #endregion

    #region Actions - Access

    /// Locking is process-local, so the grants and the session records that name
    /// the policy have to meet in the same process: the device attaches its
    /// grants to every session it shows. A borrowed workspace inherits its
    /// source's authority; nothing else can substitute one.
    internal void AttachAccess(SpaceAccessAuthority authority) {
        ArgumentNullException.ThrowIfNull(authority);
        lock (Gate) {
            if (access is not null && !ReferenceEquals(access, authority))
                throw new InvalidOperationException("A session consults one set of grants.");
            access = authority;
        }
    }

    /// The Space profile a request to unlock `spaceId` names, and whether its
    /// policy asks for authentication. Throws `Rejected` with `UnknownSpace`
    /// for a Space the session does not hold, and `SpaceBeingDeleted` for one
    /// that is going away.
    internal (SpaceAccessAssignment Assignment, bool RequiresAuthentication) Unlockable(Guid spaceId) {
        lock (Gate) {
            var space = session.Spaces.FirstOrDefault(candidate => candidate.Id == spaceId) ?? throw new Rejected(new UnknownSpace(spaceId));
            if (PendingDeletion(session, spaceId) is not null || borrowedSource?.IsDeleting(spaceId) == true)
                throw new Rejected(new SpaceBeingDeleted(spaceId));
            return (new(space.Id, space.ProfileId), space.Settings.RequiresAuthentication);
        }
    }

    #endregion
}
