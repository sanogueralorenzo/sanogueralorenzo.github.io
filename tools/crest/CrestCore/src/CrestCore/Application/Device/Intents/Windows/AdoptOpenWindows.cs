using CrestCore.Application;

namespace CrestCore.Contracts;

/// Carries the windows an installed release of the Chromium composition kept
/// open for its next launch, `WindowIds` in the order it opened them, into the
/// device store once, as the saved windows the next launch reopens, the last
/// in front. A device that already keeps windows to reopen, as one the other
/// composition ran on does, keeps its own. The store is written before the
/// intent returns; it publishes nothing, and a device that has adopted them
/// before changes nothing.
public sealed record AdoptOpenWindows(IReadOnlyList<Guid> WindowIds) : WindowIntent {
    #region Actions - Device

    /// Seeds the windows to reopen from `WindowIds` once, saving them with the
    /// adoption's marker before returning. A device without a file, or one
    /// that adopted them before, changes nothing.
    internal override void Apply(Device device, DeviceTurn turn) {
        if (device.Storage is not { } target) return;
        DeviceRecords carried;
        lock (device.Gate) {
            if (device.Adopted.Contains(DeviceAdoption.OpenWindows)) return;
            var records = device.Records();
            carried = (records.Reopening.Count > 0 ? records : records with { Reopening = [.. WindowIds.Distinct()] })
                .Adopting(DeviceAdoption.OpenWindows);
        }
        try {
            target.SaveDevice(carried);
        } catch (StorageException error) {
            throw new Rejected(new SaveFailed(error.Reason));
        }
        lock (device.Gate) {
            if (device.Reopening.Count == 0) device.Reopening.AddRange(carried.Reopening);
            device.Adopted.Add(DeviceAdoption.OpenWindows);
        }
    }

    #endregion
}
