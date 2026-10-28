using CrestCore.Application;

namespace CrestCore.Contracts;

/// The transport starts under `RecordSchema`, the newest record schema it
/// reads and writes. A cursor and server fields kept under an older schema
/// are left behind, so records the older build skipped are fetched again and
/// no upload builds on a server copy it could not read; everything else is
/// kept.
///
/// The first time, it carries the state an installed release kept in the
/// transport's own file into the device store: `Legacy` is that file exactly
/// as the host read it, or null when there is none. A pause older builds kept
/// for an ordinary record race is dropped. The state and the adoption's
/// marker are saved together, and the file is never changed, so a release
/// from before this one still reads it. Later, `Legacy` is ignored and the
/// host need not read the file: `CloudTransportState.IsAdopted` says so. A
/// file that does not read is `LegacyCloudStateUnreadable`, and nothing is
/// adopted.
[MessageLimit(128 * 1024 * 1024)]
public sealed record OpenCloudTransport(int RecordSchema, byte[]? Legacy) : CloudTransportIntent {
    #region Actions - Sync

    /// Starts the transport under the schema it reads, adopting the installed
    /// release's file the first time. The caller holds the lock.
    private void Open(CloudTransportStore transport) {
        if (!transport.Adopted) {
            var (legacy, fields) = Legacy is { } bytes
                ? LegacyCloudTransportDocument.Read(bytes, RecordSchema)
                : (CloudTransportRecord.Initial(RecordSchema), []);
            bool recovers = transport.Storage is { CloudRecoveryRequested: true };
            if (recovers) (legacy, fields) = (legacy.Recovering(), []);
            if (transport.ResetsOnAdoption && !legacy.AwaitsAccountDecision)
                (legacy, fields) = (CloudTransportRecord.Initial(RecordSchema), []);
            transport.Save(legacy, new CloudFieldWrite(Clearing: true, fields, []), DeviceAdoption.CloudTransport);
            transport.Adopted = true;
            transport.ResetsOnAdoption = false;
            transport.Device.NoteAdopted(DeviceAdoption.CloudTransport);
            transport.NeedsRecovery = transport.Record.RequiresFullPull;
            if (recovers) transport.Storage!.ConsumeCloudRecovery();
            return;
        }
        if (transport.Record.RecordSchema < RecordSchema)
            transport.Save(transport.Record with { RecordSchema = RecordSchema, EngineState = null }, CloudFieldWrite.Cleared);
    }

    #endregion

    #region Actions - Routing

    internal override IReadOnlyList<Change> Apply(CloudTransportStore transport, Func<bool> journalHoldsUploads) =>
        transport.Changing(() => Open(transport));

    #endregion
}
