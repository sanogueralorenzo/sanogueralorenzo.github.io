using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

internal sealed partial class Device {
    #region Actions - Intents

    /// Runs one window intent, publishing what it changed to the turn's changes.
    public void Handle(WindowIntent intent, DeviceTurn turn) => intent.Apply(this, turn);

    internal static void Publish(IEnumerable<Change> published, ChangeFeed changes) {
        foreach (var change in published) changes.Publish(change);
    }

    #endregion

    #region Actions - Queries

    /// The palette of a window at `now`: over the Space it shows, unless that
    /// Space is locked or being deleted, leaving out the tab it shows there,
    /// under the device's app-wide preferences and with what the Space's
    /// palette remembers, offering the workspace's other Spaces to switch to.
    public Palette Palette(Guid windowId, bool allowsInternalPages, DateTimeOffset now) {
        var window = Opened(windowId);
        var authority = Workspace(window.WorkspaceId);
        Guid spaceId;
        Guid? shown;
        lock (gate) {
            spaceId = window.ShownSpaceId;
            shown = window.Tab(spaceId);
        }
        var session = authority.Current;
        var space = Available(session, spaceId);
        if (space is not null && authority.IsLocked(space)) space = null;
        var others = session.Spaces.Where(other => other.Id != spaceId && Available(session, other.Id) is not null).ToList();
        var preferences = PersistentPreferences() ?? session.AppPreferences ?? AppPreferences.Default;
        return new(space, shown, authority.Kind.IsPrivate, allowsInternalPages, preferences, SearchCatalog, MemoryOf(spaceId), others, now);
    }

    /// The rule that would refuse `intent` in `authority` now, or null when it
    /// would be accepted. The identities a check draws are never used.
    internal static Rejection? Refusal(NativeSessionAuthority authority, SessionIntent intent, DateTimeOffset now, Pages pages) {
        try {
            authority.Check(intent, now, new SystemIdSource(), pages);
            return null;
        } catch (Rejected refused) {
            return refused.Rejection;
        }
    }

    #endregion

    #region Actions - Lookup

    /// The open window, or `WindowNotOpen`.
    internal Window Opened(Guid windowId) {
        lock (gate) return open.TryGetValue(windowId, out var window) ? window : throw new Rejected(new WindowNotOpen(windowId));
    }

    /// Where the open window stands in `spaceId`, or in the Space it shows
    /// when that is null: its workspace, that Space, and the tab it shows
    /// there, if any. Null for a window that is not open.
    internal (Guid WorkspaceId, Guid SpaceId, Guid? TabId)? Showing(Guid windowId, Guid? spaceId) {
        lock (gate) {
            if (!open.TryGetValue(windowId, out var window)) return null;
            var shown = spaceId ?? window.ShownSpaceId;
            return (window.WorkspaceId, shown, window.Tab(shown));
        }
    }

    /// The open window over the workspace that returns the person to a tab of
    /// `spaceId`: `hostId`, the window that hosts the tab's page, while it is
    /// open; else one that shows the Space; else any. Null when no window over
    /// the workspace is open, since returning to a tab never opens one.
    internal Guid? ReturnWindow(Guid workspaceId, Guid spaceId, Guid hostId) {
        lock (gate) {
            var windows = open.Values.Where(window => window.WorkspaceId == workspaceId).ToArray();
            return (windows.FirstOrDefault(window => window.Id == hostId)
                ?? windows.FirstOrDefault(window => window.ShownSpaceId == spaceId)
                ?? windows.FirstOrDefault())?.Id;
        }
    }

    /// The attached workspace, or `UnknownWorkspace`.
    internal NativeSessionAuthority Workspace(Guid workspaceId) {
        lock (gate)
            return workspaces.TryGetValue(workspaceId, out var authority) ? authority : throw new Rejected(new UnknownWorkspace(workspaceId));
    }

    /// The tabs the open windows over the workspace show on screen: the cards
    /// of the Space each one shows.
    internal IReadOnlySet<Guid> OnScreenTabs(Guid workspaceId) {
        // The session is read outside the device lock, as the windows' rules read it.
        if (Attached(workspaceId)?.Current is not { } session) return new HashSet<Guid>();
        lock (gate)
            return open.Values.Where(window => window.WorkspaceId == workspaceId).SelectMany(window => window.OnScreen(session))
                .ToHashSet();
    }

    /// Whether a window over the workspace shows `tabId` of `spaceId` on
    /// screen: the Space is the one it shows, and it shows the tab or another
    /// member of the tab's split.
    internal bool Shows(Guid workspaceId, Guid spaceId, Guid tabId) {
        lock (gate) {
            if (workspaces.GetValueOrDefault(workspaceId)?.Current.Spaces.FirstOrDefault(space => space.Id == spaceId) is not { } space)
                return false;
            var split = space.Tabs.FirstOrDefault(tab => tab.Id == tabId)?.SplitGroupId;
            return open.Values.Any(window => window.WorkspaceId == workspaceId && window.ShownSpaceId == spaceId
                && window.Tab(spaceId) is { } shown
                && (shown == tabId || split is not null && space.Tabs.Any(tab => tab.Id == shown && tab.SplitGroupId == split)));
        }
    }

    /// The one Space of `profileId` the person may see: held by an attached
    /// workspace, not locked and not being deleted. Null when no Space or more
    /// than one holds the profile.
    internal Guid? OnlySpaceOf(Guid profileId) => OnlyShowableSpaceOf(profileId)?.SpaceId;

    /// The one Space of `profileId` the person may see, with the workspace
    /// that owns it rather than one that borrows it: held by an attached
    /// workspace, not locked and not being deleted. Null when no Space or more
    /// than one holds the profile.
    internal (Guid WorkspaceId, Guid SpaceId)? OnlyShowableSpaceOf(Guid profileId) {
        KeyValuePair<Guid, NativeSessionAuthority>[] attached;
        lock (gate) attached = [.. workspaces];
        var owners = attached.OrderByDescending(workspace => workspace.Value.Kind.OwnsSpaces)
            .SelectMany(workspace => workspace.Value.Current.Spaces.Where(space => space.ProfileId == profileId)
                .Select(space => (Workspace: workspace, Space: space))).DistinctBy(owner => owner.Space.Id).ToList();
        if (owners.Count != 1) return null;
        var (owner, only) = owners[0];
        return owner.Value.IsDeleting(only.Id) || owner.Value.IsLocked(only) ? null : (owner.Key, only.Id);
    }

    /// The workspaces closing the windows `windowIds` leaves without an open
    /// window, of a kind whose pages go with their windows, so each goes with
    /// its last window, and every page of it with that window.
    internal IReadOnlySet<Guid> EndingWorkspaces(IReadOnlySet<Guid> windowIds) {
        ArgumentNullException.ThrowIfNull(windowIds);
        lock (gate) {
            var ending = open.Values.Where(window => windowIds.Contains(window.Id)).Select(window => window.WorkspaceId).ToHashSet();
            ending.RemoveWhere(workspaceId => workspaces.GetValueOrDefault(workspaceId)?.Kind.SharesPagesAcrossWindows != false
                || open.Values.Any(window => window.WorkspaceId == workspaceId && !windowIds.Contains(window.Id)));
            return ending;
        }
    }

    /// The attached workspace, or null for one that is gone.
    internal NativeSessionAuthority? Attached(Guid workspaceId) {
        lock (gate) return workspaces.GetValueOrDefault(workspaceId);
    }

    /// The workspace the person's own Spaces live in: the session the core
    /// keeps in its file, or in a launch that keeps nothing, the one that keeps
    /// the app's preferences in its place. Null while neither is attached.
    internal (Guid WorkspaceId, NativeSessionAuthority Authority)? Persistent() {
        lock (gate) {
            if (persistentWorkspace is { } kept && workspaces.TryGetValue(kept, out var stored)) return (kept, stored);
            return workspaces.Where(attached => attached.Value.Kind.KeepsAppPreferences)
                .Select(attached => ((Guid, NativeSessionAuthority)?)(attached.Key, attached.Value)).FirstOrDefault();
        }
    }

    /// The Space a window may show: one the session holds that is not being deleted.
    internal static SpaceState? Available(SessionState session, Guid spaceId) =>
        session.SpaceDeletions.Any(deletion => deletion.SpaceId == spaceId) ? null : session.Spaces.FirstOrDefault(space => space.Id == spaceId);

    #endregion
}
