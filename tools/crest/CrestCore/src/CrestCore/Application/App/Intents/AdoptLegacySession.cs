using CrestCore.Application;

namespace CrestCore.Contracts;

/// Gives a session file that holds no session its first one: the session the
/// installed release kept in its defaults, carried once with its history and
/// sync journal, or when there is nothing to carry `Seed`, or without one the
/// session a first launch starts with (`FirstInstallSession`). An installed
/// session that does not decode stays where it is and the seed stands in; the
/// core then leaves the cloud-recovery marker beside the file, so the cloud
/// transport replaces the seed with a full pull instead of uploading it as a
/// deletion of every Space the cloud still holds. The file is written before
/// the intent returns. A core whose file already holds a session, or that
/// keeps nothing on disk, publishes nothing.
///
/// `Seed` is a session a platform builds, such as an isolated run's fixture:
/// its fields alone, as a platform sends any record the core resolves values
/// of, with each Space's history inside it.
///
/// It is the one message that carries a whole session with its history and
/// journal, so it may take as much as one stored session part. An installed
/// release kept each value in its defaults, which hold a few megabytes a value
/// in practice: a session core and a journal of up to about 4 MiB each and a
/// full history of about 2 MiB a Space.
[MessageLimit(64 * 1024 * 1024)]
public sealed record AdoptLegacySession(LegacySession Installed, SessionState? Seed) : Intent {
    #region Actions - App

    /// Gives a file that holds no session its first one, before returning:
    /// the installed release's, or the seed. See `AdoptLegacySession`.
    private void Adopt(CrestApp app, ChangeFeed changes) {
        if (app.Storage is not { } target || app.StoredSession is not null) return;
        // A file that holds a session this core could not take over is refused
        // at creation, so one found here was written by an adoption whose
        // takeover failed: it is as unreadable now as it was then.
        if (target.HoldsSession) throw new Rejected(new StorageUnreadable(StorageFailure.Damaged));
        var first = FirstSession.For(this, () => FirstSession.FirstInstall(app.Ids.Next, app.Clock.Now));
        try {
            if (first.RequestsCloudRecovery) target.RequestCloudRecovery();
            target.Install(first.Session, first.Journal);
        } catch (StorageException error) {
            throw new Rejected(new SaveFailed(error.Reason));
        } catch (IOException) {
            throw new Rejected(new SaveFailed(StorageFailure.Unavailable));
        } catch (UnauthorizedAccessException) {
            throw new Rejected(new SaveFailed(StorageFailure.ReadOnly));
        }
        app.Establish(first.Session, first.Journal, first.LegacySelection);
        changes.Publish(new SessionAdopted(first.Favicons));
    }

    #endregion

    #region Actions - Routing

    internal override IReadOnlyList<Change> Route(CrestApp app) => app.Turn(changes => Adopt(app, changes));

    #endregion
}
