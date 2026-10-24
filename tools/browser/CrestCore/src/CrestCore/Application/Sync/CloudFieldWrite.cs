using CrestCore.Contracts;

namespace CrestCore.Application;

/// A change of the server fields the device store keeps: every record's
/// forgotten first when `Clearing`, then `Updated` kept and `Removed`
/// forgotten.
internal sealed record CloudFieldWrite(bool Clearing, IReadOnlyList<CloudRecordFields> Updated, IReadOnlyList<string> Removed) {
    #region Static Variables

    /// Every record's server fields forgotten.
    public static readonly CloudFieldWrite Cleared = new(Clearing: true, [], []);

    #endregion
}
