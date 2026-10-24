namespace CrestCore.Contracts;

/// What setup is doing within its step: waiting on the person, reading a
/// browser's data, importing a review, or finishing. A phase travels as its
/// index in `All`, so `All` is append-only.
public sealed class SetupPhase {
    #region Static Variables

    public static readonly SetupPhase Idle = new(name: "idle", isBusy: false);
    /// Reading the current browser of the import queue, which the platform does.
    public static readonly SetupPhase Reading = new(name: "reading", isBusy: true);
    public static readonly SetupPhase Reviewing = new(name: "reviewing", isBusy: false);
    /// Importing the review, and the passwords the platform imports with it.
    public static readonly SetupPhase Committing = new(name: "committing", isBusy: true);

    public static IReadOnlyList<SetupPhase> All { get; } = [Idle, Reading, Reviewing, Committing];

    #endregion

    #region Variables

    public string Name { get; }

    /// Whether setup is busy, so the person cannot change what it works on.
    public bool IsBusy { get; }

    #endregion

    #region Constructors

    private SetupPhase(string name, bool isBusy) {
        Name = name;
        IsBusy = isBusy;
    }

    #endregion

    #region Actions - Lookup

    public static SetupPhase? Named(string? name) => All.FirstOrDefault(phase => phase.Name == name);

    #endregion
}
