using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// This device's site permission choices. The device store keeps the
/// persistent session's choices, and only on a device with a file; every other
/// Space's choices (private, seeded, or one no attached session holds) live in
/// memory until the process ends. A borrowed workspace shows its owner's
/// Space, so its choices are the owner's. A Space's lock comes from the
/// session that holds it; a Space no session holds has no lock of its own.
internal sealed partial class Device {
    #region Variables

    /// The persistent session's choices, which the device store keeps.
    private readonly SitePermissionLedger keptPermissions = new();
    internal SitePermissionLedger KeptPermissions => keptPermissions;
    /// Every other Space's choices, which live as long as the process.
    private readonly SitePermissionLedger passingPermissions = new();
    internal SitePermissionLedger PassingPermissions => passingPermissions;

    #endregion

    #region Actions - Site permission intents

    /// Runs one site permission intent, publishing each Space it changed.
    public void Handle(SitePermissionIntent intent, DeviceTurn turn) => intent.Apply(this, turn);

    #endregion

    #region Actions - Site permission queries

    public SitePermissionAnswer Answer(SiteDecision question) {
        ArgumentNullException.ThrowIfNull(question);
        var (keeps, locked) = ChoiceScope(question.SpaceId);
        lock (gate)
            return new((keeps ? keptPermissions : passingPermissions).Decision(question.SpaceId, question.Origin, question.Permission,
                question.Detail, locked));
    }

    public SitePermissionAnswer Answer(CaptureDecision question) {
        ArgumentNullException.ThrowIfNull(question);
        var (keeps, locked) = ChoiceScope(question.SpaceId);
        lock (gate)
            return new((keeps ? keptPermissions : passingPermissions).MediaDecision(question.SpaceId, question.Origin, question.Media,
                locked));
    }

    #endregion

    #region Actions - Choice scope

    /// Whether the device store keeps `spaceId`'s site permission and engine
    /// choices, and whether this process holds no grant to show the Space. The persistent session is
    /// asked first, since a borrowed workspace holds its Space too. Called
    /// without the device lock, since it reads the sessions.
    internal (bool Keeps, bool Locked) ChoiceScope(Guid spaceId) {
        Guid? persistent;
        KeyValuePair<Guid, NativeSessionAuthority>[] attached;
        lock (gate) {
            persistent = persistentWorkspace;
            attached = [.. workspaces.OrderByDescending(entry => entry.Key == persistent)];
        }
        foreach (var (workspaceId, authority) in attached) {
            if (authority.Current.Spaces.FirstOrDefault(space => space.Id == spaceId) is not { } space) continue;
            return (storage is not null && workspaceId == persistent, authority.IsLocked(space));
        }
        return (false, false);
    }

    /// Whether `spaceId` is a private window's Space. Called without the
    /// device lock, since it reads the sessions.
    internal bool IsPrivate(Guid spaceId) {
        NativeSessionAuthority[] attached;
        lock (gate)
            attached = [.. workspaces.Values];
        return attached.Any(authority => authority.IsPrivateBrowsing && authority.Current.Spaces.Any(space => space.Id == spaceId));
    }

    /// Publishes each Space `outcome` touched with the choices it keeps now.
    /// The caller holds the device lock.
    internal void PublishPermissions(SitePermissionOutcome outcome, ChangeFeed changes) {
        foreach (var touched in outcome.Changes.GroupBy(change => change.Space))
            changes.Publish(new SitePermissionsChanged(touched.Key, PermissionRecords(touched.Key), [.. touched.Select(change => change.Scope)]));
    }

    /// The choices `space` keeps, in the order the settings list them. The
    /// caller holds the device lock.
    internal IReadOnlyList<SitePermissionRecordState> PermissionRecords(Guid space) =>
        [.. keptPermissions.Records(space).Concat(passingPermissions.Records(space)).Order(SitePermissionRecordOrder.Instance)
            .Select(record => record.State)];

    #endregion
}
