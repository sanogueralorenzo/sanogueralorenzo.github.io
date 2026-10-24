using CrestCore.Application;
using CrestCore.Contracts;

namespace CrestCore.Tests.Seeded;

// A contract record another record holds is one of the core's contracts, so
// these fixtures hold the core's archived tab, whose tab has resolved values.

/// A message the platform sends that holds a record the core resolves values of.
public sealed record KeepTab(ArchivedTabState Archived) : Intent {
    #region Actions - Routing

    /// A schema fixture is never sent.
    internal override IReadOnlyList<Change> Route(CrestApp app) => throw new NotSupportedException();

    #endregion
}

/// The same record as a change the core writes, which no platform builds.
public sealed record TabKept(ArchivedTabState Archived) : Change;

/// A message the platform sends that claims a value only the core resolves.
public sealed record Resolving(double Level) : Intent {
    #region Variables

    [Resolved]
    public double Share => Level / 2;

    #endregion

    #region Actions - Routing

    /// A schema fixture is never sent.
    internal override IReadOnlyList<Change> Route(CrestApp app) => throw new NotSupportedException();

    #endregion
}
