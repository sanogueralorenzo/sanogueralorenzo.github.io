namespace CrestCore.Contracts;

#region Queries

/// Whether the window a page opened comes to the front.
public sealed record OpenedWindowSelected(bool Selects);

/// The regular window and current Space an external link, document or system
/// sign-in uses. OpensWindow asks the shell to reopen the selected window.
public sealed record ExternalOpenPlacement(Guid? WindowId, Guid? SpaceId, bool OpensWindow);

#endregion

#region Models

/// How a link was followed: whether a person activated it, whether it loads
/// the whole page, the modifier keys held, and whether it was a middle click.
public sealed record LinkGesture(bool UserActivated, bool TopLevel, ShortcutModifiers Modifiers, bool MiddleClick);

/// What following a link does.
public sealed record LinkNavigationAnswer(LinkNavigationDecision Decision);

#endregion
