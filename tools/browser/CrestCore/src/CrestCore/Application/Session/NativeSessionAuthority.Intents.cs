using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

#region Types

/// What one session intent changes: the next session, how it stages (null
/// for an edit no journal ever reads), what the window that issued it
/// shows next, what it did that the two states cannot tell, the sweep it
/// records, and the Quick Window or Peek page it kept or archived.
internal sealed record SessionEdit(SessionState Next, SyncStaging? Staging, WindowFollowUp? FollowUp = null,
    SessionTabEvents? Events = null, NativeSessionAuthority.SweepMark? Sweep = null, Guid? Completes = null);

/// What one session intent's edit reads: the accepted session it edits, the
/// time it is stamped with, where new identities come from, what the device's
/// pages show, and whether an import is only previewed, which reads Spaces
/// this process has not unlocked.
internal sealed record SessionTurn(SessionState Basis, DateTimeOffset Now, IIdSource Ids, Pages? Pages, bool Previewed);

#endregion

public sealed partial class NativeSessionAuthority {
    #region Actions - Intents

    /// Runs one session intent at `now`, drawing new identities from `ids`
    /// and reading what the device's `pages` show, such as the Quick Window
    /// and Peek pages an intent names, and commits what it changed, which the
    /// device publishes. An intent that changes nothing commits nothing, and
    /// publishes only what it did that the session cannot tell, such as the
    /// image a tab now wears, and what its window shows next, such as the tab
    /// it returns to after putting a saved tab's page away. Throws `Rejected`
    /// naming the rule that refused it, or `SaveFailed` for an edit saved
    /// before it returns whose save failed, which changed nothing.
    internal void Handle(SessionIntent intent, DateTimeOffset now, IIdSource ids, Pages? pages = null) {
        ArgumentNullException.ThrowIfNull(intent);
        ArgumentNullException.ThrowIfNull(ids);
        try {
            if (intent.MovedAcross(this, Stamp(now), commits: true)) return;
        } catch (StorageException error) {
            throw new Rejected(new SaveFailed(error.Reason));
        }
        SessionEdit? edit;
        SessionState previous;
        NativeSessionReplacement? reserved = null;
        // The edit is accepted, or reserved while it is saved, under the lock
        // that computed it, so nothing else can commit in between.
        lock (Gate) {
            edit = Edit(intent, Stamp(now), ids, pages);
            if (edit is null) return;
            if (edit.Sweep is { } sweep) lastSweep = sweep;
            previous = session;
            if (edit.Next.Equals(previous)) {
                if (edit.Events is null && edit.FollowUp is null) return;
            } else if (edit.Staging is { Urgency.StagesWithSave: true }) {
                reserved = Reserve(edit.Next, edit.Completes, edit.FollowUp, edit.Events);
            } else {
                if (edit.Completes is { } completed) completedTransients.Add(completed);
                _ = Accept(edit.Next);
            }
        }
        if (reserved is not null) {
            try {
                SaveStaged(reserved, previous, edit.Staging!);
            } catch (StorageException error) {
                throw new Rejected(new SaveFailed(error.Reason));
            }
            return;
        }
        var events = edit.Events ?? SessionTabEvents.None;
        if (edit.Next.Equals(previous)) {
            Published(previous, previous, edit.FollowUp, events);
            return;
        }
        Published(previous, edit.Next, edit.FollowUp, events);
        QueueStage(previous, edit.Next, edit.Staging);
    }

    /// Throws the `Rejected` that would refuse `intent` at `now`, and changes
    /// nothing. New identities come from `ids`, and are never used.
    internal void Check(SessionIntent intent, DateTimeOffset now, IIdSource ids, Pages? pages = null) {
        ArgumentNullException.ThrowIfNull(intent);
        ArgumentNullException.ThrowIfNull(ids);
        if (!intent.MovedAcross(this, Stamp(now), commits: false)) lock (Gate) _ = Edit(intent, Stamp(now), ids, pages);
    }

    /// The edit an intent makes to the accepted session, validated, or null
    /// for a sweep the last one makes unnecessary. `pages` are what the
    /// device's windows show, which a copy of a tab starts from. An import
    /// `previewed` reads Spaces this process has not unlocked, as a person
    /// sees them before they import. The caller holds the gate.
    private SessionEdit? Edit(SessionIntent intent, DateTimeOffset now, IIdSource ids, Pages? pages, bool previewed = false) {
        var basis = IntentBasis();
        var edit = intent.Edit(this, new SessionTurn(basis, now, ids, pages, previewed));
        if (edit is null) return null;
        if (intent.ValidatesWholeSession) Validate(edit.Next);
        else Validate(basis, edit.Next);
        ValidateBorrowedSession(edit.Next);
        return edit;
    }

    /// The accepted session an intent edits. A borrowed Space takes its
    /// owner's current settings, as a refresh would, since an intent proposes
    /// no settings of its own.
    private SessionState IntentBasis() {
        if (released) throw new Rejected(new UnknownWorkspace(workspaceId));
        if (replacement is not null) throw new Rejected(new WorkspaceBusy(workspaceId));
        if (borrowedSource is not { } source) return session;
        var original = source.session.Spaces.SingleOrDefault(space => space.Id == borrowedSpace);
        if (source.released || original is null || original.ProfileId != borrowedProfile)
            throw new Rejected(new UnknownSpace(borrowedSpace));
        if (PendingDeletion(source.session, borrowedSpace) is not null) throw new Rejected(new SpaceBeingDeleted(borrowedSpace));
        var local = session.Spaces.Single();
        var refreshed = BorrowedSpace(original, local);
        return refreshed == local ? session : session with { Spaces = [refreshed] };
    }

    /// The Space an intent edits: one `basis` holds that is not being deleted,
    /// and, unless the edit only maintains it, one this process may read.
    internal SpaceState Editable(SessionState basis, Guid spaceId, bool maintains = false) {
        var space = basis.Spaces.FirstOrDefault(candidate => candidate.Id == spaceId) ?? throw new Rejected(new UnknownSpace(spaceId));
        if (PendingDeletion(basis, spaceId) is not null) throw new Rejected(new SpaceBeingDeleted(spaceId));
        if (!maintains && IsLockedUnderGate(space)) throw new Rejected(new SpaceLocked(spaceId));
        return space;
    }

    /// The Spaces an intent that names none edits: every one `basis` holds that
    /// is not being deleted, and, unless the edit only maintains them, that
    /// this process may read.
    internal IEnumerable<SpaceState> EditableSpaces(SessionState basis, bool maintains = false) =>
        basis.Spaces.Where(space => PendingDeletion(basis, space.Id) is null && (maintains || !IsLockedUnderGate(space)));

    /// The window that issued an intent, as it is now, or null when it is not
    /// open over this workspace.
    internal Window? IssuingWindow(Guid windowId) => device?.Snapshot(workspaceId, windowId);

    /// `now` as the session stores it, so the next load reads the same value.
    private static DateTimeOffset Stamp(DateTimeOffset now) => StoredSessionCodec.Date(StoredSessionCodec.Seconds(now));

    #endregion
}
