using CrestCore.Application;

namespace CrestCore.Contracts;

/// An intent from the cloud transport about its own state on this device:
/// the engine's saved cursor, the last server fields of each record it
/// uploads over, whether a download must be recovered with a full pull,
/// whether an account change waits for the person's decision, and whether
/// this device's copy overwrites the cloud's. The device store keeps it
/// beside the session and never syncs it.
///
/// The transport sends one from its own thread, never the host's; the core
/// takes no lock the host's intents wait for. Each is on disk before it
/// returns, and a save that fails is `SaveFailed` and changes nothing. Its
/// answer carries `CloudTransportChanged` with the state it left, which
/// never reaches the host's state.
public abstract record CloudTransportIntent : Intent {
    #region Abstract Methods

    /// Runs the intent on the transport's state, saving what it changed before
    /// it returns, and answers the state it left. `journalHoldsUploads` tells
    /// whether the stored session's journal still holds records waiting to
    /// upload, once every stage queued before settled.
    internal abstract IReadOnlyList<Change> Apply(CloudTransportStore transport, Func<bool> journalHoldsUploads);

    #endregion

    #region Actions - Routing

    /// Runs on the transport's thread, outside the app's turns.
    internal sealed override IReadOnlyList<Change> Route(CrestApp app) => app.CloudTransport.Handle(this, app.JournalHoldsUploads);

    #endregion
}
