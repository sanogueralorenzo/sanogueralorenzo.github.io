using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Where a link another app hands Crest opens, over this device's windows as
/// the platform stacks them, frontmost first (`WindowIds`): the first enabled
/// route that matches and whose Space can open, else the external-link
/// destination, both read from this device's preferences, in the persistent
/// session's Spaces. A link never opens in a locked Space on another app's
/// behalf: it opens in a Quick Window on the Space on screen when that one is
/// unlocked, else on the first unlocked Space, and nowhere when every Space is
/// locked.
///
/// The link goes to the frontmost window over the persistent session, never a
/// private or torn-off tab's window, and a Quick Window promotes into it. With
/// none open it goes where it would with one open: a Quick Window alone, or a
/// window a person would open, which opens.
public sealed record RouteExternalLink(IReadOnlyList<Guid> WindowIds, string Url) : Query<ExternalLinkPlacement> {
    #region Actions - Answering

    /// Where a link another app hands Crest opens, under this device's
    /// preferences and the persistent session's Spaces: none being deleted,
    /// and never a locked one.
    internal override ExternalLinkPlacement Answer(CrestApp app) {
        var nowhere = new ExternalLinkPlacement(null, false, false, null, false);
        if (app.Device.Persistent() is not (_, var authority)) return nowhere;
        var session = authority.Current;
        var spaces = session.Spaces;
        var front = app.Device.FrontWindow(WindowIds);
        Guid? opening = null;
        LinkPreferences preferences;
        lock (app.Device.Gate) {
            if (front is null) opening = app.Device.WindowToOpen(app.Ids);
            preferences = app.Device.Links;
        }
        var shown = front?.ShownSpaceId ?? app.Device.OpeningSpace(opening!.Value, session) ?? Guid.Empty;
        var context = new LinkRoutingContext([.. spaces.Select(space => space.Id)], shown,
            [.. spaces.Where(space => authority.IsDeleting(space.Id)).Select(space => space.Id)]);
        var locked = spaces.Where(authority.IsLocked).Select(space => space.Id).ToHashSet();
        if (preferences.RouteExternal(Url, context, locked) is not { } placed) return nowhere;
        return front is { } window
            ? new(placed.SpaceId, placed.OpensQuickWindow, placed.SubstitutesForLockedSpace, window.Id, OpensWindow: false)
            : placed.OpensQuickWindow
                ? new(placed.SpaceId, true, placed.SubstitutesForLockedSpace, null, OpensWindow: false)
                : new(placed.SpaceId, false, placed.SubstitutesForLockedSpace, opening, OpensWindow: true);
    }

    #endregion
}
