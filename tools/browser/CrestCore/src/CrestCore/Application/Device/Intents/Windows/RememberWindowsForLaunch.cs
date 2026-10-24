using CrestCore.Application;

namespace CrestCore.Contracts;

/// Keeps the saved windows open now for the next launch to reopen, in the
/// order the platform stacks them: `WindowIds`, frontmost first. A saved
/// window open but not stacked, such as a minimized one, reopens behind the
/// stacked ones; windows that are not open or not saved are passed over. The
/// device store is written before the intent returns, as a quit needs; it
/// publishes nothing.
public sealed record RememberWindowsForLaunch(IReadOnlyList<Guid> WindowIds) : WindowIntent {
    #region Actions - Device

    /// Orders the saved windows open now back to front, as the platform stacks
    /// them, and saves them for the next launch before returning, under the
    /// device lock so no records handed to the store earlier land after them.
    /// Refused with `SaveFailed` when the device store cannot be written.
    internal override void Apply(Device device, DeviceTurn turn) {
        lock (device.Gate) {
            var open = device.OpenWindows.Values.Where(window => window.Saved).Select(window => window.Id).ToHashSet();
            var stacked = WindowIds.Distinct().Where(open.Contains).Reverse().ToList();
            var behind = device.Reopening.Where(id => open.Contains(id) && !stacked.Contains(id))
                .Concat(open.Where(id => !stacked.Contains(id) && !device.Reopening.Contains(id)));
            device.Reopening.Clear();
            device.Reopening.AddRange([.. behind, .. stacked]);
            if (device.Storage is not { } target) return;
            try {
                target.SaveDevice(device.Records());
            } catch (StorageException error) {
                throw new Rejected(new SaveFailed(error.Reason));
            }
        }
    }

    #endregion
}
