using CrestCore.Application;

namespace CrestCore.Contracts;

/// The cloud transport's state on this device.
public sealed record CloudTransport : Query<CloudTransportState> {
    #region Variables

    /// The transport store keeps a lock of its own.
    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override CloudTransportState Answer(CrestApp app) {
        lock (app.CloudTransport.Gate) return app.CloudTransport.Record.Published(app.CloudTransport.Adopted);
    }

    #endregion
}
