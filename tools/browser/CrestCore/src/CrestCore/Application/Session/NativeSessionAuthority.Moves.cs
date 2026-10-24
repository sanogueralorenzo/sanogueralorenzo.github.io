using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Types

    /// One workspace's part in a move between windows: the state it held, and
    /// the one reserved for it while the move is saved.
    private sealed record MoveSide(NativeSessionAuthority Workspace, SessionState Previous, NativeSessionReplacement Reserved);

    /// What one workspace's part in a move between windows leaves it with,
    /// and what the window it shows there shows next.
    private sealed record MovePart(SessionState Next, WindowFollowUp FollowUp);

    #endregion

    #region Actions - Moving between windows

    /// The workspace the window a tab moves to shows, when it is another one;
    /// null when it shows this one. Refused with `WindowNotOpen` for a window
    /// that is gone.
    internal NativeSessionAuthority? Receiving(MoveTabToWindow intent) {
        Device? shown;
        lock (Gate) shown = device;
        if (shown is null) throw new Rejected(new WindowNotOpen(intent.DestinationWindowId));
        var receiving = shown.Workspace(shown.Opened(intent.DestinationWindowId).WorkspaceId);
        return ReferenceEquals(receiving, this) ? null : receiving;
    }

    /// Moves the tab out of this workspace into `receiving`, the workspace the
    /// destination window shows, when `commits`; otherwise only checks that it
    /// would. Both workspaces change together or neither does; see
    /// `CommitAcross`.
    internal void MovingAcross(NativeSessionAuthority receiving, MoveTabToWindow intent, DateTimeOffset now, bool commits) {
        MoveSide leaving, arriving;
        lock (Gate) {
            var (left, arrived) = Across(receiving, intent, now);
            if (!commits) return;
            leaving = new(this, session, Reserve(left.Next, completes: null, left.FollowUp, events: null));
            try {
                arriving = new(receiving, receiving.session,
                    receiving.Reserve(arrived.Next, completes: null, arrived.FollowUp, events: null));
            } catch {
                leaving.Reserved.Dispose();
                throw;
            }
        }
        CommitAcross(leaving, arriving);
    }

    /// The states that take the tab out of this workspace and into
    /// `receiving`, each against its accepted state. The tab joins the open
    /// tabs after the one the destination window shows, which then shows it in
    /// its Space; the window it left shows the tab it showed before. The
    /// caller holds the gate.
    private (MovePart Leaving, MovePart Arriving) Across(NativeSessionAuthority receiving,
        MoveTabToWindow intent, DateTimeOffset now) {
        var basis = IntentBasis();
        var theirs = receiving.IntentBasis();
        if (privateBrowsing != receiving.privateBrowsing) throw new Rejected(new PrivateWorkspaceBoundary(receiving.workspaceId));
        if (borrowedSource is null && receiving.borrowedSource is null
            || !ReferenceEquals(borrowedSource ?? this, receiving.borrowedSource ?? receiving))
            throw new Rejected(new UnrelatedWorkspaces(receiving.workspaceId));
        var space = Editable(basis, intent.SpaceId);
        var there = receiving.Editable(theirs, intent.SpaceId);
        if (space.Tabs.All(tab => tab.Id != intent.TabId)) throw new Rejected(new UnknownTab(intent.TabId));
        if (theirs.Spaces.Any(candidate => candidate.Tabs.Any(tab => tab.Id == intent.TabId)
            || candidate.ArchivedTabs.Any(archived => archived.Tab.Id == intent.TabId)))
            throw new Rejected(new TabAlreadyExists(intent.TabId));
        var leaving = new WindowFollowUp(IssuingWindow(intent.WindowId));
        var arriving = new WindowFollowUp(receiving.IssuingWindow(intent.DestinationWindowId));
        var edited = BrowserTabCollection.Restore(space);
        var receivingTabs = BrowserTabCollection.Restore(there);
        var fallback = leaving.FallbackAfterDismissing(space.Id, intent.TabId,
            space.Tabs.Select(tab => tab.Id).Where(id => id != intent.TabId).ToHashSet());
        var shown = edited.TransferTo(receivingTabs, intent.TabId, leaving.Window?.Tab(space.Id), fallback, TabPlacement.Current,
            requestedFolder: null, before: null, afterSelection: true, arriving.Window?.Tab(there.Id), now);
        receivingTabs.Tab(intent.TabId).Activate(now);
        edited.PruneSplitMetadata();
        receivingTabs.PruneSplitMetadata();
        leaving.ShowTab(space.Id, shown);
        arriving.ShowTab(there.Id, intent.TabId).ShowSpace(there.Id);
        var next = Replacing(basis, edited.Capture(space));
        var nextThere = Replacing(theirs, receivingTabs.Capture(there));
        Validate(basis, next);
        ValidateBorrowedSession(next);
        receiving.Validate(theirs, nextThere);
        receiving.ValidateBorrowedSession(nextThere);
        return (new(next, leaving), new(nextThere, arriving));
    }

    /// Accepts both reserved states together. The workspace that owns the
    /// Spaces, when one of the two does, keeps the file and the journal: its
    /// state stages and is saved with that journal first, and a failed stage
    /// or save leaves both workspaces as they were. A workspace that borrows
    /// keeps neither. Both then publish what they changed.
    private static void CommitAcross(MoveSide leaving, MoveSide arriving) {
        var keeper = leaving.Workspace.borrowedSource is null ? leaving : arriving.Workspace.borrowedSource is null ? arriving : null;
        NativeSyncTransaction? staged = null;
        try {
            if (keeper is { Workspace: var owner, Previous: var previous, Reserved: var kept }) {
                staged = owner.StageWithSave(previous, kept.Session, SyncStaging.Transfer.Reason);
                if (staged is not null) kept.BindSync(staged);
                owner.storage?.Save(kept.Session, kept.Revision, kept.SyncTransaction?.Journal, kept.Checkpoint);
            }
        } catch {
            leaving.Reserved.Dispose();
            arriving.Reserved.Dispose();
            staged?.Dispose();
            throw;
        }
        SessionState left, arrived;
        lock (Gate) {
            left = leaving.Reserved.Complete();
            arrived = arriving.Reserved.Complete();
        }
        foreach (var (side, previous) in new[] { (leaving, left), (arriving, arrived) })
            side.Workspace.Published(previous, side.Reserved.Session, side.Reserved.FollowUp, side.Reserved.Events);
        staged?.Owner.AnnounceStaged();
    }

    #endregion
}
