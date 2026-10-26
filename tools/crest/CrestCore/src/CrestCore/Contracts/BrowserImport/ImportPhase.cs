namespace CrestCore.Contracts;

/// What setup is doing within its step: waiting on the person, reading a
/// browser's data, importing a review, or finishing. A phase travels as its
/// index in `All`, so `All` is append-only.
public sealed class ImportPhase {
    #region Static Variables

    public static readonly ImportPhase Idle = new(name: "idle", isBusy: false);
    /// Reading the current browser of the import queue, which the platform does.
    public static readonly ImportPhase Reading = new(name: "reading", isBusy: true);
    public static readonly ImportPhase Reviewing = new(name: "reviewing", isBusy: false);
    public static readonly ImportPhase Committing = new(name: "committing", isBusy: true);

    public static IReadOnlyList<ImportPhase> All { get; } = [Idle, Reading, Reviewing, Committing];

    #endregion

    #region Variables

    public string Name { get; }

    /// Whether setup is busy, so the person cannot change what it works on.
    public bool IsBusy { get; }

    #endregion

    #region Constructors

    private ImportPhase(string name, bool isBusy) {
        Name = name;
        IsBusy = isBusy;
    }

    #endregion

    #region Actions - Lookup

    public static ImportPhase? Named(string? name) => All.FirstOrDefault(phase => phase.Name == name);

    #endregion
}
