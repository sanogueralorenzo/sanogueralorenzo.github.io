using CrestCore.Domain;

namespace CrestCore.Application;

internal static class NativeEditTimestamp {
    #region Variables

    private const double SwiftEpochOffset = 978307200;

    #endregion

    #region Actions - Session

    internal static double Encode(DateTimeOffset value) =>
        BrowserEditTimestamp.NormalizeUnixSeconds((value - DateTimeOffset.UnixEpoch).TotalSeconds) - SwiftEpochOffset;

    #endregion
}
