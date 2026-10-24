using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - Spaces

    internal SpaceDeletionState? PendingDeletion(SessionState value, Guid spaceId) =>
        value.SpaceDeletions.FirstOrDefault(deletion => deletion.SpaceId == spaceId);

    /// `space` with `settings`, keeping the settings it had when nothing
    /// changed, so an edit that changes nothing publishes nothing.
    internal SpaceState Configured(SpaceState space, SpaceSettings settings) =>
        settings == space.Settings ? space : space with { Settings = settings };

    /// Refuses a Space intent a borrowed workspace cannot apply: the
    /// workspace it borrows from owns the Space's profile and its settings,
    /// and makes, orders and deletes Spaces.
    internal void RequireOwnedSpaces() {
        if (!workspaceKind.OwnsSpaces) throw new Rejected(new BorrowedProfileRequiresOwner(workspaceId));
    }

    /// `basis` with the Space an intent edited in its place.
    internal SessionEdit SettingSpace(SessionState basis, SpaceState space, Func<SpaceSettings, SpaceSettings> edit, SyncStaging staging) =>
        new(Replacing(basis, Configured(space, edit(space.Settings))), staging);

    #endregion

    #region Actions - Space deletion

    /// The Space a deletion names, locked or not, and its deletion under way.
    internal (SpaceState Space, SpaceDeletionState? Pending) Deleting(SessionState basis, Guid spaceId) =>
        (basis.Spaces.FirstOrDefault(space => space.Id == spaceId) ?? throw new Rejected(new UnknownSpace(spaceId)),
            PendingDeletion(basis, spaceId));

    #endregion
}
