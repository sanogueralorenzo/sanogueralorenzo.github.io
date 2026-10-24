using CrestCore.Application;
using CrestCore.Contracts;

namespace CrestCore.Tests.Narrowed;

/// Moves among the intents: a query holds one of them and no other intent.
public abstract record Move(Guid Piece) : Intent {
    #region Actions - Routing

    /// A schema fixture is never sent.
    internal override IReadOnlyList<Change> Route(CrestApp app) => throw new NotSupportedException();

    #endregion
}

public sealed record Slide(Guid Piece, int Squares) : Move(Piece);

public sealed record Jump(Guid Piece) : Move(Piece);

public sealed record Resign : Intent {
    #region Actions - Routing

    /// A schema fixture is never sent.
    internal override IReadOnlyList<Change> Route(CrestApp app) => throw new NotSupportedException();

    #endregion
}

/// Whether the move is legal.
public sealed record MoveCheck(Move Move) : Query<bool> {
    #region Actions - Answering

    /// A schema fixture is never asked.
    internal override bool Answer(CrestApp app) => throw new NotSupportedException();

    #endregion
}
