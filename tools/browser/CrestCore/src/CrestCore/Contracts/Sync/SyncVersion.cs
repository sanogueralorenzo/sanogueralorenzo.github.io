namespace CrestCore.Contracts;

/// One version of a synced record: the logical clock of the device that wrote
/// it, then that device. Versions order by clock, then by the device, so every
/// client picks the same winner between two writes.
public sealed record SyncVersion(ulong Clock, Guid DeviceId) : IComparable<SyncVersion> {
    #region Actions - Ordering

    /// Orders by clock, then by the devices' lowercase spellings, which order
    /// exactly as the Apple clients' uppercase ones do.
    public int CompareTo(SyncVersion? other) {
        if (other is null) return 1;
        int clock = Clock.CompareTo(other.Clock);
        return clock != 0 ? clock : string.Compare(DeviceId.ToString("D"), other.DeviceId.ToString("D"), StringComparison.Ordinal);
    }

    #endregion
}
