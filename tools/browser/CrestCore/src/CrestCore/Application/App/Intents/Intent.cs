using CrestCore.Application;

namespace CrestCore.Contracts;

/// A request to change the core's state. The core answers it with the changes
/// it caused, or refuses it with one rejection.
public abstract record Intent {
    #region Abstract Methods

    /// Runs the intent in `app` and answers the changes it published: most
    /// in one of the app's turns, under its lock, and the cloud transport's on
    /// their own.
    internal abstract IReadOnlyList<Change> Route(CrestApp app);

    #endregion
}
