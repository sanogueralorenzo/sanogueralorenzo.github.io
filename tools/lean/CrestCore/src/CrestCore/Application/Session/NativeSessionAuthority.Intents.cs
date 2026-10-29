using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

#region Types

internal sealed record SessionEdit(SessionState Next, SyncStaging? Staging, WindowFollowUp? FollowUp = null,
    SessionTabEvents? Events = null, NativeSessionAuthority.SweepMark? Sweep = null);

internal sealed record SessionTurn(SessionState Basis, DateTimeOffset Now, IIdSource Ids);

#endregion

public sealed partial class NativeSessionAuthority {
    #region Actions - Intents

    internal void Handle(SessionIntent intent, DateTimeOffset now, IIdSource ids) {
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
            edit = Edit(intent, Stamp(now), ids);
            if (edit is null) return;
            if (edit.Sweep is { } sweep) lastSweep = sweep;
            previous = session;
            if (edit.Next.Equals(previous)) {
                if (edit.Events is null && edit.FollowUp is null) return;
            } else if (edit.Staging is { Urgency.StagesWithSave: true }) {
                reserved = Reserve(edit.Next, edit.FollowUp, edit.Events);
            } else {
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
    internal void Check(SessionIntent intent, DateTimeOffset now, IIdSource ids) {
        ArgumentNullException.ThrowIfNull(intent);
        ArgumentNullException.ThrowIfNull(ids);
        if (!intent.MovedAcross(this, Stamp(now), commits: false)) lock (Gate) _ = Edit(intent, Stamp(now), ids);
    }

    private SessionEdit? Edit(SessionIntent intent, DateTimeOffset now, IIdSource ids) {
        var basis = IntentBasis();
        var edit = intent.Edit(this, new SessionTurn(basis, now, ids));
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
        var original = source.session.Space(borrowedSpace);
        if (source.released || original is null || original.ProfileId != borrowedProfile)
            throw new Rejected(new UnknownSpace(borrowedSpace));
        if (source.session.PendingDeletion(borrowedSpace) is not null) throw new Rejected(new SpaceBeingDeleted(borrowedSpace));
        var local = session.Spaces.Single();
        var refreshed = BorrowedSpace(original, local);
        return refreshed == local ? session : session with { Spaces = [refreshed] };
    }

    /// The Space an intent edits: one `basis` holds that is not being deleted,
    internal SpaceState Editable(SessionState basis, Guid spaceId) {
        var space = basis.Spaces.FirstOrDefault(candidate => candidate.Id == spaceId) ?? throw new Rejected(new UnknownSpace(spaceId));
        if (basis.PendingDeletion(spaceId) is not null) throw new Rejected(new SpaceBeingDeleted(spaceId));
        return space;
    }

    /// The Spaces an intent that names none edits: every one `basis` holds that
    /// is not being deleted.
    internal IEnumerable<SpaceState> EditableSpaces(SessionState basis) =>
        basis.Spaces.Where(space => basis.PendingDeletion(space.Id) is null);

    /// The window that issued an intent, as it is now, or null when it is not
    /// open over this workspace.
    internal Window? IssuingWindow(Guid windowId) => device?.Snapshot(workspaceId, windowId);

    /// `now` as the session stores it, so the next load reads the same value.
    private static DateTimeOffset Stamp(DateTimeOffset now) => StoredSessionCodec.Date(StoredSessionCodec.Seconds(now));

    #endregion
}
