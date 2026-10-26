using CrestCore.Application;

namespace CrestCore.Contracts;

/// An intent about this device's shortcut choices. The device store keeps
/// them beside the session, never in it, and they never sync. Only the
/// commands this device offers, those its default engine can perform, hold or
/// lose a chord.
public abstract record ShortcutIntent : Intent {
    #region Abstract Methods

    /// Runs the intent on the device's shortcut choices, over the commands
    /// the turn says this device offers, publishing the bindings when any of
    /// them changed.
    internal abstract void Apply(Device device, ShortcutTurn turn);

    #endregion

    #region Actions - Routing

    /// The bindings are read over the commands the registered engines offer.
    internal sealed override IReadOnlyList<Change> Route(CrestApp app) => app.Turn(changes =>
        app.Device.Handle(this, new ShortcutTurn(changes, Engines.OfferedCommands(app.RegisteredEngines()))));

    #endregion
}
