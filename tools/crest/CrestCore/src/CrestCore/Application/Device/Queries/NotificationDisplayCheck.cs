using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Whether a notification a document at `Origin` posted in a page of the
/// Space `SpaceId` shows, whichever engine hosts the page: only from a secure
/// origin whose notifications the Space allows. A private window's Space never
/// shows one, whatever it allows, so a private window posts nothing to the
/// system's notifications.
public sealed record NotificationDisplayCheck(Guid SpaceId, SiteOrigin Origin) : Query<NotificationDisplayVerdict> {
    #region Actions - Answering

    internal override NotificationDisplayVerdict Answer(CrestApp app) =>
        new(Origin.IsSecureContext && !app.Device.IsPrivate(SpaceId)
            && app.Device.Answer(new SiteDecision(SpaceId, Origin, SitePermission.Notifications, Detail: null)).Decision.Grants);

    #endregion
}
