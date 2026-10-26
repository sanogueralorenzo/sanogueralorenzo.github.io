using CrestCore.Application;

namespace CrestCore.Contracts;

/// The fixed bindings of the commands this device's engines offer.
public sealed record GetShortcuts() : Query<ShortcutsChanged> {
    #region Actions - Answering

    internal override ShortcutsChanged Answer(CrestApp app) =>
        app.Device.Shortcuts(Engines.OfferedCommands(app.RegisteredEngines()));

    #endregion
}
