namespace CrestCore.Contracts;

/// The page's popup state after the event, or null when nothing changed.
public sealed record BlockedPopupTransitioned(BlockedPopupPageState? State);

/// What the notification request leads to.
public sealed record NotificationRequestAnswer(HostedNotificationRequestAction Action);

/// Whether the origin is secure enough for the capability.
public sealed record SecureOriginVerdict(bool Allowed);

/// A blocked-popup state or event the notice cannot hold.
public sealed record InvalidBlockedPopup : Rejection;

/// Let a request through, stop it, or ask the person.
public enum SitePermissionVerdict { Ask, Grant, Deny }
