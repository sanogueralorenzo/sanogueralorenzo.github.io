namespace CrestCore.Contracts;

/// How hard the system is asking for memory back. A level travels as its
/// index in `All`, so `All` is append-only.
public sealed class MemoryPressureLevel {
    #region Variables

    public static readonly MemoryPressureLevel Warning = new(name: "warning", severity: 1, releasesActiveTransientPages: false);
    public static readonly MemoryPressureLevel Critical = new(name: "critical", severity: 2, releasesActiveTransientPages: true);

    public static IReadOnlyList<MemoryPressureLevel> All { get; } = [Warning, Critical];

    public string Name { get; }

    /// How severe the level is: a more severe level escalates a squeeze the
    /// store already answered.
    public int Severity { get; }

    /// A Quick Window or Peek the person is using gives its page back too; a
    /// milder squeeze keeps it.
    public bool ReleasesActiveTransientPages { get; }

    #endregion

    #region Constructors

    private MemoryPressureLevel(string name, int severity, bool releasesActiveTransientPages) {
        Name = name;
        Severity = severity;
        ReleasesActiveTransientPages = releasesActiveTransientPages;
    }

    #endregion
}
