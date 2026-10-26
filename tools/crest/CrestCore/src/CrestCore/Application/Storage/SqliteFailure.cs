using CrestCore.Contracts;

namespace CrestCore.Application;

/// The SQLite result codes the core reports as something other than an
/// unavailable file. Each member names the primary code and the reason it means.
internal sealed class SqliteFailure {
    #region Variables

    public static readonly SqliteFailure Busy = new(code: 5, StorageFailure.Busy);
    public static readonly SqliteFailure Locked = new(code: 6, StorageFailure.Busy);
    public static readonly SqliteFailure ReadOnly = new(code: 8, StorageFailure.ReadOnly);
    public static readonly SqliteFailure Corrupt = new(code: 11, StorageFailure.Damaged);
    public static readonly SqliteFailure Full = new(code: 13, StorageFailure.DiskFull);
    public static readonly SqliteFailure NotADatabase = new(code: 26, StorageFailure.Damaged);
    public static IReadOnlyList<SqliteFailure> All { get; } = [Busy, Locked, ReadOnly, Corrupt, Full, NotADatabase];

    /// Extended result codes keep the primary code in their low byte.
    private const int PrimaryMask = 0xff;

    public int Code { get; }
    public StorageFailure Reason { get; }

    #endregion

    #region Constructors

    private SqliteFailure(int code, StorageFailure reason) {
        Code = code;
        Reason = reason;
    }

    #endregion

    #region Actions - Classification

    /// What a failed call's result means for the session's storage.
    public static StorageFailure ReasonFor(int result) =>
        All.FirstOrDefault(failure => failure.Code == (result & PrimaryMask))?.Reason ?? StorageFailure.Unavailable;

    #endregion
}
