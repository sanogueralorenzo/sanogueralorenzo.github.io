namespace CrestCore.Contracts;

#region Queries

/// The page's popup state after the event, or null when the event changed
/// nothing and the page keeps its state and shows no new indication.
public sealed record BlockedPopupTransitioned(BlockedPopupPageState? State);

/// The choice that answers a site permission question.
public sealed record SitePermissionAnswer(SitePermissionDecision Decision);

/// What the notification request leads to.
public sealed record NotificationRequestAnswer(HostedNotificationRequestAction Action);

/// Whether a notification a document posted shows.
public sealed record NotificationDisplayVerdict(bool Shows);

/// Whether the origin is secure enough for the capability.
public sealed record SecureOriginVerdict(bool Allowed);

#endregion

#region Changes

/// A Space's site permission choices changed. `Records` are the choices it
/// keeps now, in the order the settings list them; `Touched` names what the
/// change covered, so a page can withdraw what it was already given.
public sealed record SitePermissionsChanged(Guid SpaceId, IReadOnlyList<SitePermissionRecordState> Records,
    IReadOnlyList<SitePermissionScope> Touched) : Change;

/// Which choices in a Space one change covered. A null member covers every
/// value, so a Space reset names none. `RevokesAuthorization` tells live pages
/// to withdraw what they were already given.
public sealed record SitePermissionScope(SiteOrigin? Origin, SitePermission? Permission, string? Detail,
    bool RevokesAuthorization);

#endregion

#region Rejections

/// A blocked-popup state or event the notice cannot hold: a status without an
/// origin or the reverse, or an indication without its document or origin.
public sealed record InvalidBlockedPopup : Rejection;

/// A site permission's origin has an empty or overlong scheme or host, or a
/// port that is not one.
public sealed record InvalidSiteOrigin(SiteOrigin Origin) : Rejection;

/// A choice's detail is empty or longer than `Limit` characters.
public sealed record InvalidSitePermissionDetail(int Limit) : Rejection;

/// A grant for `Permission`, which the system asks the person about each
/// time, so a site can only be blocked from it.
public sealed record InvalidSitePermissionGrant(SitePermission Permission) : Rejection;

/// This device already keeps `Limit` saved site permission choices.
public sealed record SitePermissionLimitReached(int Limit) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized(Argument = nameof(Limit))]
    public string Message => "Crest can keep up to %lld saved site permissions. Reset some to save more.";

    #endregion
}

#endregion

#region Models

/// What a site permission decision says about a request: let it through, stop
/// it, or ask the person.
public enum SitePermissionVerdict { Ask, Grant, Deny }

#endregion
