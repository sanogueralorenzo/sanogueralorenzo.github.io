using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class CrestApp {
    #region Actions - Workspaces

    /// Runs one workspace intent. What it changes joins the pending batch in
    /// the order it happened: a closing workspace's pages, then its windows,
    /// then that it closed; an opening workspace whole, then the tabs its
    /// repair gave a new identity. The caller holds the lock.
    internal void Handle(WorkspaceIntent intent) => intent.Apply(this);

    /// Opens a workspace over `seed`, repaired as the file's session is when
    /// it loads. A tab the repair gave a new identity follows as `TabCopied`
    /// from the tab whose image it wears.
    internal void OpenSeeded(WorkspaceKind kind, SessionState seed) {
        var (session, copies) = Seeded(seed);
        var workspaceId = ids.Next();
        device.Attach(new NativeSessionAuthority(kind, session), workspaceId);
        foreach (var (source, copy) in copies) Announce(new TabCopied(workspaceId, source, copy));
    }

    /// Opens the session this core keeps in its file, then attaches the sync
    /// component it stages into, so the transport hears the launch stage. A
    /// session already open publishes itself again.
    internal void OpenStored() {
        if (storedSession is not { } session) throw new Rejected(new NoStoredSession());
        if (device.Identity(session) is { } open) {
            Announce(new WorkspaceOpened(open, session.Kind, session.Current));
            return;
        }
        if (session.IsReleased) throw new Rejected(new StoredSessionClosed());
        var workspaceId = ids.Next();
        device.AttachPersistent(session, storedSelection, workspaceId);
        session.AttachSync(storedSync!);
        foreach (var (source, copy) in repairedCopies) Announce(new TabCopied(workspaceId, source, copy));
    }

    /// `session`, a seed, repaired as the file's session is when it loads,
    /// with each tab the repair gave a new identity and the tab it came from.
    /// Throws `Rejected` with `InvalidSession` naming the first rule it breaks
    /// that the repair cannot mend.
    private (SessionState Session, IReadOnlyList<(Guid Source, Guid Copy)> Copies) Seeded(SessionState session) {
        var now = StoredSessionCodec.Date(StoredSessionCodec.Seconds(clock.Now));
        SessionState repaired;
        IReadOnlyList<NativeSessionMaintenance.TabOrigin> origins;
        try {
            repaired = NativeSessionMaintenance.Repair(session, now, null, ids, out origins);
        } catch (BrowserRuleException) {
            // A Space whose deletion is under way keeps its identities, so one
            // another Space shares is the seed's to fix.
            throw new Rejected(new InvalidSession(SessionIdentities.Flaw(session) ?? SessionFlaw.Unreadable));
        }
        if (SessionIdentities.Flaw(repaired) is { } flaw) throw new Rejected(new InvalidSession(flaw));
        return (repaired, NativeSessionMaintenance.Copies(repaired, origins));
    }

    /// The session a workspace of `kind` starts with when it keeps no file and
    /// has no seed: one Space of its kind's template, or the practice Space
    /// for the practice, stamped as the session stores the time.
    internal SessionState Template(WorkspaceKind kind) {
        var now = StoredSessionCodec.Date(StoredSessionCodec.Seconds(clock.Now));
        var template = kind.IsPractice ? SpaceTemplate.Practice : SpaceTemplate.For(kind.IsPrivate);
        var space = template.Make(ids.Next(), ids.Next(), ids.Next, number: 1, now);
        return new([space], DefaultSpaceId: null, DisposableSeedMarker: null, SpaceDeletions: [], AppPreferences: null);
    }

    /// Closes a workspace and, first, every workspace that borrows from it:
    /// its session takes no edits, its pages go and their engines close what
    /// they hold, then its windows close, keeping their saved records, and its
    /// sync stops once its queued stages ran. The caller holds the lock.
    internal void Close(Guid workspaceId) {
        if (device.Attached(workspaceId) is not { } session) return;
        foreach (var borrower in device.Borrowers(session)) Close(borrower);
        session.Close();
        var dropped = new ChangeFeed();
        pages.Drop(workspaceId, dropped, Issue);
        PublishEngines(dropped.Publish);
        foreach (var change in dropped.Published) Announce(change);
        device.Detach(workspaceId);
        if (ReferenceEquals(session, storedSession)) storedSync?.Stop();
    }

    /// A borrowed workspace whose owner no longer lends its Space closes. Only
    /// an intent changes an owner's session, so the intent holds the lock here
    /// and delivers what the close issued once it lets go.
    private void CloseBorrower(Guid workspaceId) {
        if (!gate.IsHeldByCurrentThread)
            throw new InvalidOperationException("A borrowed workspace closes only inside the intent that ended its loan.");
        Close(workspaceId);
    }

    /// The workspace `workspaceId` names.
    internal NativeSessionAuthority Workspace(Guid workspaceId) => device.Workspace(workspaceId);

    #endregion
}
