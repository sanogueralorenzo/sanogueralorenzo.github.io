using CrestCore.Application;

namespace CrestCore.Contracts;

/// Something the platform tells the core about iCloud sync on this device:
/// what the person asked for, and what each step the core asked for came to.
/// The core decides what sync does next and answers `CloudSyncAdvanced`: the
/// status it left and the steps the platform takes, in order, reporting each
/// one's result back. A step names the attempt it belongs to, and a result
/// for an attempt that is no longer current changes only what the core says
/// it must.
public abstract record CloudSyncControlIntent : Intent {
    #region Abstract Methods

    /// Moves the control's state on, and answers the steps the platform takes
    /// next, in order. The control holds its lock.
    internal abstract List<CloudSyncStep> Steps(CloudSyncControl control);

    #endregion

    #region Actions - Routing

    /// Runs outside the app's turns.
    internal sealed override IReadOnlyList<Change> Route(CrestApp app) => app.CloudSync.Handle(this);

    #endregion
}
