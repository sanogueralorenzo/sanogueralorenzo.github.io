using CrestCore.Contracts;

namespace CrestCore.Application;

/// The session's storage could not read or write the file. `Reason` is what the
/// core publishes or answers; the message keeps SQLite's own text for logs.
public sealed class StorageException(StorageFailure reason, string message) : Exception(message) {
    #region Variables

    public StorageFailure Reason { get; } = reason;

    #endregion
}
