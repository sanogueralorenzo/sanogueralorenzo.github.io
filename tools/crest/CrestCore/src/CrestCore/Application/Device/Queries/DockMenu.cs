using CrestCore.Application;

namespace CrestCore.Contracts;

/// The Dock icon's menu, over this device's windows as the platform stacks
/// them, frontmost first (`WindowIds`; a window the device does not have open
/// is passed over). It lists the window commands, then the persistent
/// session's Spaces in the session's order, leaving out one being deleted, as
/// the Space switcher does.
///
/// A private window keeps to itself. None of its Spaces is listed, and with
/// one in front, as with a Blank Window, no Space is checked, because the
/// frontmost window shows none of these. A chosen Space shows in the
/// frontmost window over the persistent session, never in a private or
/// borrowed one, and opens a window on itself only when no such window is
/// open.
public sealed record DockMenu(IReadOnlyList<Guid> WindowIds) : Query<DockMenuContent> {
    #region Actions - Answering

    /// The window commands, the persistent session's Spaces with the one the
    /// frontmost window shows checked, and the window a chosen Space shows in.
    internal override DockMenuContent Answer(CrestApp app) {
        if (app.Device.Persistent() is not (var workspaceId, var authority)) return new(DockMenuCommand.All, [], null);
        Guid? shown, target;
        lock (app.Device.Gate) {
            var stacked = WindowIds.Select(id => app.Device.OpenWindows.GetValueOrDefault(id)).OfType<Window>().ToList();
            shown = stacked.FirstOrDefault() is { } front && front.WorkspaceId == workspaceId ? front.ShownSpaceId : null;
            target = stacked.FirstOrDefault(window => window.WorkspaceId == workspaceId)?.Id;
        }
        // The session's own locks are taken only once the device's is released.
        var spaces = authority.Current.Spaces.Where(space => !authority.IsDeleting(space.Id))
            .Select(space => new DockMenuSpace(space.Id, space.ProfileId, space.Settings.Name, space.Settings.Symbol,
                space.Settings.Accent, space.Settings.Look, IsShown: space.Id == shown, IsLocked: authority.IsLocked(space)));
        return new(DockMenuCommand.All, [.. spaces], target);
    }

    #endregion
}
