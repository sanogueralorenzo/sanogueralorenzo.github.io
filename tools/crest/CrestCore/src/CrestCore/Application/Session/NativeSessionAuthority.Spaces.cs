using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - Spaces

    /// Refuses a Space intent a borrowed workspace cannot apply: the
    /// workspace it borrows from owns the Space's profile and its settings,
    /// and makes, orders and deletes Spaces.
    internal void RequireOwnedSpaces() {
        if (!workspaceKind.OwnsSpaces) throw new Rejected(new BorrowedProfileRequiresOwner(workspaceId));
    }

    /// `basis` with the Space an intent edited in its place.
    internal SessionEdit SettingSpace(SessionState basis, SpaceState space, Func<SpaceSettings, SpaceSettings> edit, SyncStaging staging) =>
        new(basis.Replacing(space.Configured(edit(space.Settings))), staging);

    #endregion

    #region Actions - Space deletion

    /// The Space a deletion names, locked or not, and its deletion under way.
    internal (SpaceState Space, SpaceDeletionState? Pending) Deleting(SessionState basis, Guid spaceId) =>
        (basis.KnownSpace(spaceId), basis.PendingDeletion(spaceId));

    #endregion
}
