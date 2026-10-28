using CrestCore.Contracts;

namespace CrestCore.Application;

/// The changes one intent published, in the order its handler made them.
public sealed class ChangeFeed {
    #region Variables

    private readonly List<Change> published = [];

    public IReadOnlyList<Change> Published => published;

    #endregion

    #region Actions - Publishing

    public void Publish(Change change) {
        ArgumentNullException.ThrowIfNull(change);
        published.Add(change);
    }

    #endregion
}
