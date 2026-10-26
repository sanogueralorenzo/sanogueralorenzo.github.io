using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Which windows a launch opens, and which one a window the person asks for
/// shows when none is open. The device store keeps the saved windows the next
/// launch reopens, back to front: opening a saved window puts it in front, and
/// closing one forgets it, unless the person agreed to quit, when every window
/// still open is one to reopen. Setup stands in front of them on a device that
/// has not completed it, or in a launch that forces it, until it finishes. A
/// quit waits for the Spaces being deleted whose data the engines still erase.
internal sealed partial class Device {
    #region Variables

    /// The saved windows the next launch reopens, back to front.
    private readonly List<Guid> reopening = [];
    internal List<Guid> Reopening => reopening;
    /// The person agreed to quit, so the windows still open are the ones the
    /// next launch reopens, and closing them as the app goes forgets none.
    private bool quitAccepted;
    /// Setup finished during this run, which opens its launch gate whatever
    /// the launch forced.
    private bool setupFinishedThisRun;

    #endregion

    #region Actions - Reopening

    /// The saved window `windowId` opened, so the next launch reopens it in
    /// front of the others. The caller holds the device lock.
    internal void Reopen(Guid windowId) {
        if (reopening.Count > 0 && reopening[^1] == windowId) return;
        reopening.Remove(windowId);
        reopening.Add(windowId);
        storage?.EnqueueDevice(Records());
    }

    /// The window `windowId` closed, so the next launch does not reopen it,
    /// unless the person agreed to quit. The caller holds the device lock.
    internal void StopReopening(Guid windowId) {
        if (quitAccepted || !reopening.Remove(windowId)) return;
        storage?.EnqueueDevice(Records());
    }

    #endregion

    #region Actions - Quitting

    /// The person agreed to quit: the windows still open are the ones the next
    /// launch reopens.
    internal void AcceptQuit() {
        lock (gate) quitAccepted = true;
    }

    /// The Spaces an attached workspace is deleting whose profile's data the
    /// engines are erasing now, as `erasing` says of each profile.
    internal IReadOnlyList<Guid> SpacesBeingDeleted(Func<Guid, bool> erasing) {
        ArgumentNullException.ThrowIfNull(erasing);
        NativeSessionAuthority[] attached;
        lock (gate) attached = [.. workspaces.Values];
        return [.. attached.SelectMany(workspace => workspace.Current.SpaceDeletions)
            .Where(deletion => erasing(deletion.ProfileId)).Select(deletion => deletion.SpaceId).Distinct()];
    }

    #endregion

    #region Actions - Launch

    /// The windows a launch opens, back to front: the saved windows the device
    /// store reopens, or with none of them, the one a window opened with none
    /// open shows.
    internal IReadOnlyList<Guid> LaunchWindows(IIdSource ids) {
        lock (gate) {
            var windows = reopening.Where(saved.ContainsKey).ToList();
            return windows.Count > 0 ? windows : [WindowToOpen(ids)];
        }
    }

    /// The window a window the person asks for shows when none over the
    /// persistent session is open: the saved window used last that is not
    /// open, or a new one. The caller holds the device lock.
    internal Guid WindowToOpen(IIdSource ids) =>
        saved.Values.Where(record => !open.ContainsKey(record.Id)).MaxBy(record => record.Used)?.Id ?? ids.Next();

    /// The frontmost of `stacked`, the windows as the platform stacks them,
    /// frontmost first, that the device has open over the persistent session,
    /// with the Space it shows; null when none is. A private window, a
    /// torn-off tab's and one the device does not have open are passed over.
    internal (Guid Id, Guid ShownSpaceId)? FrontWindow(IReadOnlyList<Guid> stacked) {
        ArgumentNullException.ThrowIfNull(stacked);
        // The persistent workspace is read before the device lock is taken for the windows.
        if (Persistent() is not (var workspaceId, _)) return null;
        lock (gate) return Frontmost(workspaceId, stacked) is { } window ? (window.Id, window.ShownSpaceId) : null;
    }

    /// The frontmost of `stacked` that the device has open over `workspaceId`,
    /// or null when none is.
    internal Guid? FrontWindowOver(Guid workspaceId, IReadOnlyList<Guid> stacked) {
        ArgumentNullException.ThrowIfNull(stacked);
        lock (gate) return Frontmost(workspaceId, stacked)?.Id;
    }

    /// The frontmost of `stacked` open over `workspaceId`. The caller holds the
    /// device lock.
    private Window? Frontmost(Guid workspaceId, IReadOnlyList<Guid> stacked) =>
        stacked.Select(id => open.GetValueOrDefault(id)).OfType<Window>().FirstOrDefault(window => window.WorkspaceId == workspaceId);

    /// The Space the saved window `windowId`, not open yet, would open on over
    /// `session`: the one its record shows while that stays, else the launch
    /// Space. Null while every Space is going.
    internal Guid? OpeningSpace(Guid windowId, SessionState session) {
        Guid? kept;
        lock (gate) kept = saved.GetValueOrDefault(windowId)?.ShownSpaceId;
        return kept is { } space && Available(session, space) is not null ? space : Window.LaunchSpace(session)?.Id;
    }

    /// The setup a launch in `environment` on `platform` opens in front of its
    /// windows, or null when it opens none: first-run setup, until it finishes
    /// in this run, on a device that has not completed it or in a launch that
    /// forces it.
    internal SetupEntry? LaunchSetup(LaunchEnvironment environment, DevicePlatform platform) {
        ArgumentNullException.ThrowIfNull(environment);
        ArgumentNullException.ThrowIfNull(platform);
        lock (gate)
            return !setupFinishedThisRun && (platform.ForcesSetup(environment) || !setupCompleted) ? SetupEntry.FirstRun : null;
    }

    #endregion
}
