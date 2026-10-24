using CrestCore.Application;

namespace CrestCore.Contracts;

/// Whether a notification without a live page may appear for a profile.
/// Native engines verify an extension's notification permission; the core
/// still requires an accessible, unambiguous, non-private Space. Web origins
/// additionally require that Space's notification grant.
public sealed record ProfileNotificationDisplayCheck(Guid ProfileId, SiteOrigin Origin, ProfileNotificationSource Source)
    : Query<NotificationDisplayVerdict> {
    #region Actions - Answering

    internal override NotificationDisplayVerdict Answer(CrestApp app) {
        if (app.Device.OnlySpaceOf(ProfileId) is not { } space || app.Device.IsPrivate(space)) return new(false);
        return Source == ProfileNotificationSource.Extension
            ? new(Origin.Scheme == "chrome-extension" && Origin.Host.Length > 0)
            : app.Query(new NotificationDisplayCheck(space, Origin));
    }

    #endregion
}
