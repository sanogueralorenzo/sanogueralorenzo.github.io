using CrestCore.Application;
using CrestCore.Contracts;

namespace CrestCore.Tests.Reordered;

/// `Ordered.Signal` with its members listed the other way round.
public sealed class Signal {
    public static readonly Signal Stop = new(name: "stop", isMoving: false);
    public static readonly Signal Go = new(name: "go", isMoving: true);
    public static IReadOnlyList<Signal> All { get; } = [Go, Stop];

    public string Name { get; }
    public bool IsMoving { get; }

    private Signal(string name, bool isMoving) {
        Name = name;
        IsMoving = isMoving;
    }
}

public sealed record ShowSignal(Signal Signal) : Intent {
    #region Actions - Routing

    /// A schema fixture is never sent.
    internal override IReadOnlyList<Change> Route(CrestApp app) => throw new NotSupportedException();

    #endregion
}
