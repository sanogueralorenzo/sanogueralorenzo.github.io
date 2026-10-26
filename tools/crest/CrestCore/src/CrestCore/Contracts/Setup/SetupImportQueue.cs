namespace CrestCore.Contracts;

/// The browsers setup imports from, in the order the platform lists them, and
/// the one it is on, at `Index`.
public sealed record SetupImportQueue(IReadOnlyList<ImportSource> Sources, int Index) {
    #region Variables

    /// The browser setup is on, or null once every one is done.
    [Resolved]
    public ImportSource? Current => Index >= 0 && Index < Sources.Count ? Sources[Index] : null;

    /// Whether another browser follows the one setup is on.
    [Resolved]
    public bool HasMoreAfterCurrent => Index + 1 < Sources.Count;

    #endregion
}
