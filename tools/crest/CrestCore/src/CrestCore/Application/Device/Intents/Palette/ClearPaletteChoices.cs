using CrestCore.Application;

namespace CrestCore.Contracts;

/// Forgets what every Space's palette learned on this device: each pick and
/// which places were typed. How often places were visited stays, as history
/// keeps it.
public sealed record ClearPaletteChoices() : PaletteIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ClearPaletteChoices();

    #endregion
}
