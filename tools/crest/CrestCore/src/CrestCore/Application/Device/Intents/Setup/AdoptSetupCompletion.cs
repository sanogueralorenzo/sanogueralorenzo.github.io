using CrestCore.Application;

namespace CrestCore.Contracts;

/// Carries whether an installed release completed setup, as it kept it under
/// `crest.onboarding.completed`, into the device store once, and publishes
/// whether this device has completed setup. A device that keeps no file keeps
/// `Completed` for this run; one that adopted it before keeps what it has.
public sealed record AdoptSetupCompletion(bool Completed) : SetupFlowIntent {
    #region Actions - Device

    /// Carries whether an installed release completed setup into the device
    /// store once, and publishes whether this device has. A device that keeps
    /// no file keeps what it is told for this run.
    internal override void Apply(Device device, DeviceTurn turn) {
        lock (device.Gate) {
            if (device.Storage is not { } target) device.SetupCompleted = Completed;
            else if (!device.Adopted.Contains(DeviceAdoption.SetupCompletion)) {
                device.SetupCompleted |= Completed;
                device.Adopted.Add(DeviceAdoption.SetupCompletion);
                target.EnqueueDevice(device.Records());
            }
            turn.Changes.Publish(new SetupCompletedChanged(device.SetupCompleted));
        }
    }

    #endregion
}
