using CrestCore.Application;

namespace CrestCore.Contracts;

/// A person in window `WindowId` picked `Row` after typing `Text`. The
/// palette of the Space the window shows remembers the address as typed and,
/// when the person lets it learn, the pick for that text. A private window,
/// or a Space the persistent session does not hold, remembers nothing.
public sealed record RecordPaletteChoice(Guid WindowId, string Text, PaletteRow Row) : PaletteIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.RecordPaletteChoice(WindowId, Text, Row, turn.Now);

    #endregion
}
