using CrestCore.Application;

namespace CrestCore.Contracts;

/// Carries the window records an installed release kept in its defaults into
/// the device store, once: what each window showed, the Spaces it had seen and
/// its split columns, folded with the selection that release kept in the
/// session. The store is written before the intent returns; a device that has
/// adopted them before publishes nothing. `Records` are the raw bytes, or
/// null when the release kept none.
public sealed record AdoptWindowRecords(byte[]? Records) : WindowIntent {
    #region Actions - Device

    /// Carries the window records an installed release kept into the device
    /// store once, saving them before returning. Older records fold in the
    /// selection that release kept in the session. A device without a file,
    /// or one that adopted them before, publishes nothing.
    internal override void Apply(Device device, DeviceTurn turn) {
        Guid workspaceId;
        if (device.Storage is not { } target) return;
        lock (device.Gate) {
            if (device.Adopted.Contains(DeviceAdoption.WindowRecords) || device.PersistentWorkspace is not { } persistent) return;
            workspaceId = persistent;
        }
        var spaces = device.Workspace(workspaceId).Current.Spaces.Select(space => space.Id).ToArray();
        var legacy = LegacyWindowRecord.DecodeAll(Records);
        DeviceRecords carried;
        long used;
        lock (device.Gate) {
            used = device.LastUse;
            var records = new Dictionary<Guid, SavedWindow>(device.SavedWindows);
            foreach (var record in legacy.Where(record => !records.ContainsKey(record.Id)))
                records[record.Id] = record.Record(spaces, device.LegacyShownTabs, ++used);
            carried = device.Records().Adopting(DeviceAdoption.WindowRecords) with {
                Windows = [.. records.Values.OrderBy(record => record.Used).TakeLast(Device.MaximumSavedWindows)]
            };
        }
        try {
            target.SaveDevice(carried);
        } catch (StorageException error) {
            throw new Rejected(new SaveFailed(error.Reason));
        }
        lock (device.Gate) {
            device.SavedWindows.Clear();
            foreach (var record in carried.Windows) device.SavedWindows[record.Id] = record;
            device.LastUse = Math.Max(device.LastUse, used);
            device.Adopted.Add(DeviceAdoption.WindowRecords);
        }
        turn.Changes.Publish(new WindowRecordsAdopted([.. legacy.Select(record => record.Layout)]));
    }

    #endregion
}
