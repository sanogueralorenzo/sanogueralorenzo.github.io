namespace CrestCore.Contracts;

#region Queries

/// Whether the window a page opened comes to the front.
public sealed record OpenedWindowSelected(bool Selects);

/// The Space an external link opens in and whether it opens as a Quick Window
/// there. `SubstitutesForLockedSpace` says the routed Space was locked and this
/// one stands in for it. `SpaceId` is null when no Space may take the link.
/// `WindowId` is the window the link opens in, or a Quick Window promotes into:
/// an open one, or with `OpensWindow`, one to open. It is null when the link
/// opens nowhere, or in a Quick Window with no window open.
public sealed record ExternalLinkPlacement(Guid? SpaceId, bool OpensQuickWindow, bool SubstitutesForLockedSpace, Guid? WindowId,
    bool OpensWindow);

/// The window and Space a document another app hands Crest opens in: an open
/// window, or with `OpensWindow`, one to open. Both are null when no Space may
/// take it.
public sealed record LocalDocumentPlacement(Guid? WindowId, Guid? SpaceId, bool OpensWindow);

#endregion

#region Changes

/// This device's link preferences changed, or were read as it opened.
public sealed record LinkPreferencesChanged(LinkPreferences Preferences) : Change;

#endregion

#region Rejections

/// A route edit gives no field, more than one, or an empty Space.
public sealed record InvalidLinkRouteEdit(Guid RouteId) : Rejection;

/// A route's pattern is longer than `Maximum` characters.
public sealed record LinkPatternTooLong(int Maximum) : Rejection;

/// A route already has this identity.
public sealed record LinkRouteExists(Guid RouteId) : Rejection;

/// No route more fits: there are already `Maximum`.
public sealed record LinkRoutesFull(int Maximum) : Rejection;

/// No route has this identity.
public sealed record UnknownLinkRoute(Guid RouteId) : Rejection;

#endregion

#region Models

/// How a link was followed: whether a person activated it, whether it loads
/// the whole page, the modifier keys held, and whether it was a middle click.
public sealed record LinkGesture(bool UserActivated, bool TopLevel, ShortcutModifiers Modifiers, bool MiddleClick);

/// What following a link does.
public sealed record LinkNavigationAnswer(LinkNavigationDecision Decision);

#endregion
