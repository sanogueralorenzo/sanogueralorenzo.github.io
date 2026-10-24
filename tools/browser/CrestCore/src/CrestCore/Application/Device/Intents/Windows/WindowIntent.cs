using CrestCore.Application;

namespace CrestCore.Contracts;

/// An intent about what one of this device's windows shows. The device owns
/// every window and what it shows; the session never holds any of it.
public abstract record WindowIntent : Intent {
    #region Abstract Methods

    /// Runs the intent on the device's windows, publishing what it changed to
    /// the turn's changes.
    internal abstract void Apply(Device device, DeviceTurn turn);

    #endregion

    #region Actions - Routing

    /// A window that comes to show a page whose renderer stopped while nobody
    /// saw it brings the page back.
    internal sealed override IReadOnlyList<Change> Route(CrestApp app) => app.Turn(changes => {
        app.Device.Handle(this, app.DeviceTurn(changes));
        app.Pages.RecoverShown(changes, app.Issue);
    });

    #endregion
}
