using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The access area: which Spaces this process may show. It keeps the one
/// grant authority the device attaches to every session it shows, so a
/// borrowed workspace and the one it borrows from unlock and lock together.
/// Each intent publishes the access of every Space profile it changed.
internal sealed class SpaceAccess(Device device, SpaceAccessAuthority authority) {
    #region Variables

    /// The device whose sessions hold the Spaces.
    internal Device Device => device;

    #endregion

    #region Actions - Intents

    /// Runs one access intent, publishing the access of every Space profile it
    /// changed.
    public void Handle(SpaceAccessIntent intent, ChangeFeed changes) => intent.Apply(this, changes);

    /// Applies `change` to the grants, holding their lock, and publishes the
    /// access of each Space profile it answers.
    internal void Changing(ChangeFeed changes, Func<SpaceAccessAuthority, IEnumerable<SpaceAccessAssignment>> change) {
        lock (authority) {
            foreach (var assignment in change(authority))
                changes.Publish(new SpaceLockChanged(assignment.Space, assignment.Profile, authority.IsUnlocked(assignment),
                    authority.IsAuthenticating(assignment)));
        }
    }

    #endregion
}
