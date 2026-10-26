using CrestCore.Application;

namespace CrestCore.Contracts;

/// The server fields the device store keeps of `RecordNames`.
public sealed record CloudFieldsOf(IReadOnlyList<string> RecordNames) : Query<CloudRecordFieldList> {
    #region Variables

    /// The transport store keeps a lock of its own.
    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    /// The server fields kept of the records asked for. Throws `Rejected`
    /// with `StorageUnreadable` when the file cannot be read.
    internal override CloudRecordFieldList Answer(CrestApp app) {
        lock (app.CloudTransport.Gate) {
            if (app.CloudTransport.Storage is not { } source) {
                var fields = app.CloudTransport.MemoryFields;
                return new([.. RecordNames.Where(fields.ContainsKey).Select(name => fields[name])]);
            }
            try {
                return new(source.CloudFields(RecordNames));
            } catch (StorageException error) {
                throw new Rejected(new StorageUnreadable(error.Reason));
            }
        }
    }

    #endregion
}
