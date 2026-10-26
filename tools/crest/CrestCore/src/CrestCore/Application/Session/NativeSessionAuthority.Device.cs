using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Variables

    /// The device whose windows show this session, and the workspace it gave
    /// it; null until attached.
    private Device? device;
    private Guid workspaceId;

    /// The device whose windows show this session; null until attached.
    internal Device? Device => device;

    /// The workspace the device gave this session.
    internal Guid WorkspaceId => workspaceId;

    /// The accepted session, for readers outside the command path.
    internal SessionState Current {
        get {
            lock (Gate) return session;
        }
    }

    /// Pages in this workspace keep nothing once they close.
    internal bool IsPrivateBrowsing => privateBrowsing;

    /// Whether `spaceId` is being deleted here or, for a borrowed workspace, in
    /// the workspace it borrows from, which owns the Space's profile.
    internal bool IsDeleting(Guid spaceId) {
        lock (Gate) return session.PendingDeletion(spaceId) is not null || borrowedSource?.IsDeleting(spaceId) == true;
    }

    #endregion

    #region Actions - Device

    internal void AttachDevice(Device value, Guid workspace) {
        lock (Gate) {
            if (device is not null && !ReferenceEquals(device, value))
                throw new InvalidOperationException("A session is shown by one device.");
            device = value;
            workspaceId = workspace;
        }
    }

    /// Publishes a change about this session's workspace through the device
    /// that shows it; a session no window shows yet publishes nothing. Called
    /// with no lock held.
    internal void Announce(Func<Guid, Change> change) {
        Device? target;
        Guid workspace;
        lock (Gate) {
            target = device;
            workspace = workspaceId;
        }
        target?.Announce(change(workspace));
    }

    /// Asks the host of the device that shows this session for a turn. Called
    /// with no lock held.
    internal void RequestTurn() {
        Device? target;
        lock (Gate) target = device;
        target?.RequestTurn();
    }

    /// The host of the device that shows this session finished a turn.
    internal void TurnEnded() {
        NativeSyncAuthority? attached;
        lock (Gate) attached = sync;
        attached?.TurnEnded();
    }

    /// Tells the device the session accepted `next` in place of `previous`,
    /// with what the command chose for the window that issued it and what it
    /// did that the two states cannot tell. Called with no lock held.
    internal void Published(SessionState previous, SessionState next, WindowFollowUp? followUp, SessionTabEvents events) {
        Device? target;
        Guid workspace;
        lock (Gate) {
            target = device;
            workspace = workspaceId;
        }
        target?.SessionPublished(workspace, previous, next, followUp, events);
    }

    /// Records that a window showed `tabId`, which current-tab cleanup reads,
    /// as a new state saved behind and staged once uses pause, and answers the
    /// state it replaced and the new one. Answers null, and changes nothing,
    /// when the Space or tab is gone, the Space is being deleted, or this
    /// session takes no edits. Throws `Rejected` for a locked Space.
    internal (SessionState Previous, SessionState Next)? Touch(Guid spaceId, Guid tabId, DateTimeOffset now) {
        SessionState previous, next;
        lock (Gate) {
            if (!TakesEdits() || session.PendingDeletion(spaceId) is not null
                || session.Space(spaceId) is not { } space
                || space.Tabs.All(tab => tab.Id != tabId)) return null;
            if (IsLockedUnderGate(space)) throw new Rejected(new SpaceLocked(spaceId));
            // The stored spelling of the time, so the next load reads the same value.
            var at = StoredSessionCodec.Date(StoredSessionCodec.Seconds(now));
            next = session.Replacing(space with {
                Tabs = [.. space.Tabs.Select(tab => tab.Id == tabId ? tab with { LastActivatedAt = at } : tab)]
            });
            previous = Accept(next);
        }
        QueueStage(previous, next, SyncStaging.TabUse);
        return (previous, next);
    }

    /// Whether this process holds no grant to show `space`.
    internal bool IsLocked(SpaceState space) {
        lock (Gate) return IsLockedUnderGate(space);
    }

    private bool IsLockedUnderGate(SpaceState space) {
        if (access is null) return false;
        lock (access) return access.IsLocked(new SpaceAccessAssignment(space.Id, space.ProfileId), space.Settings.RequiresAuthentication);
    }

    #endregion
}
