using CrestCore.Application;
using CrestCore.Contracts;

namespace CrestCore.Tests.Opened;

/// A set whose members also come from a factory at runtime.
[OpenSet]
public sealed class Engine {
    public const string MadePrefix = "made:";

    public static readonly Engine Built = new("built", "Built In");
    public static IReadOnlyList<Engine> All { get; } = [Built];

    public string Name { get; }
    public string Title { get; }

    private Engine(string name, string title) {
        Name = name;
        Title = title;
    }

    public static Engine Made(string name) => new(MadePrefix + name, name);
}

/// A runtime member has no index in `All`, so no message may carry one.
public sealed record SendEngine(Engine Value) : Intent {
    #region Actions - Routing

    /// A schema fixture is never sent.
    internal override IReadOnlyList<Change> Route(CrestApp app) => throw new NotSupportedException();

    #endregion
}
