using CrestCore.Contracts;

namespace CrestCore.Application;

/// The cloud transport's state as the device store keeps it: the record
/// schema its cursor and server fields were read under, and what
/// `CloudTransportState` publishes of it.
internal sealed record CloudTransportRecord(int RecordSchema, bool RequiresFullPull, bool AwaitsAccountDecision,
    bool OverwritesCloud, byte[]? EngineState) {
    #region Actions - Transitions

    /// A transport that starts over under `recordSchema`.
    public static CloudTransportRecord Initial(int recordSchema) => new(recordSchema, false, false, false, null);

    /// This state after a restored or replaced session: nothing the transport
    /// kept describes it any more, so it pulls everything again, and an
    /// account decision still waits.
    public CloudTransportRecord Recovering() => this with { RequiresFullPull = true, OverwritesCloud = false, EngineState = null };

    /// What the platform reads of this state.
    public CloudTransportState Published(bool isAdopted) =>
        new(RequiresFullPull, AwaitsAccountDecision, OverwritesCloud, EngineState, isAdopted);

    #endregion
}
