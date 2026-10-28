using CrestCore.Application;

namespace CrestCore.Contracts;

/// Erases everything every engine keeps for profile `ProfileId`: cookies,
/// storage, caches and the stores themselves. An `Ephemeral` profile keeps
/// nothing on disk. A Space's deletion finishes only once its profile's data
/// is erased this way.
public sealed record DeleteProfileData(Guid RequestId, Guid ProfileId, bool Ephemeral) : DataDeletionIntent(RequestId) {
    #region Actions - Data deletion

    /// Until every engine erases it again, the profile's data is not known gone.
    internal override void Apply(DataDeletions deletions, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        deletions.ErasedProfiles.Remove(ProfileId);
        deletions.Start(new(RequestId, ProfileId), erasure => new EraseProfileData(ProfileId, Ephemeral, erasure), changes, issue);
    }

    #endregion
}
