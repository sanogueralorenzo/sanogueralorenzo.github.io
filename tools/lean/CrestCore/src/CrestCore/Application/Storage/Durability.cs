namespace CrestCore.Application;

/// When an accepted session revision must be on disk. Every accepted revision
/// is saved; a durability that waits for disk saves it before the revision is
/// published and the call returns, for commits whose effects outside the core
/// depend on the file: sync commits, whose journal an upload follows, and Space
/// deletion, before and after the engine erases the profile's data.
public sealed class Durability {
    #region Variables

    /// Saved by the storage worker after the revision is published.
    public static readonly Durability WriteBehind = new(waitsForDisk: false);
    /// Saved before the revision is published; a failed save refuses the commit.
    public static readonly Durability BeforeReturn = new(waitsForDisk: true);
    public static IReadOnlyList<Durability> All { get; } = [WriteBehind, BeforeReturn];

    public bool WaitsForDisk { get; }

    #endregion

    #region Constructors

    private Durability(bool waitsForDisk) => WaitsForDisk = waitsForDisk;

    #endregion
}
