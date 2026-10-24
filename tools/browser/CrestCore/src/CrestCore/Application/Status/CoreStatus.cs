namespace CrestCore.Application;

/// Shared status codes for the synchronous native entry points. These values
/// must stay identical to the CREST_* macros in CrestContracts/include/crest_core.h.
public static class CoreStatus {
    #region Variables

    public const int Ok = 0, Empty = 1, BufferTooSmall = 2, Timeout = 3, Stopped = 4, Busy = 5, Rejected = 6,
        InvalidArgument = -1, VersionMismatch = -2, InvalidState = -3, InvalidHandle = -4,
        InvalidMessage = -5, InternalError = -6, LimitExceeded = -7, StorageFailed = -8;

    #endregion
}
