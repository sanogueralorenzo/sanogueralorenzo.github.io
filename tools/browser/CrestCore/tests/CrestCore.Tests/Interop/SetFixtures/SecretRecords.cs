using CrestCore.Application;
using CrestCore.Contracts;

namespace CrestCore.Tests.Secret;

/// A password.
[HoldsSecrets]
public sealed record Unlock(string Owner, string Password) : Intent {
    #region Actions - Routing

    /// A schema fixture is never sent.
    internal override IReadOnlyList<Change> Route(CrestApp app) => throw new NotSupportedException();

    #endregion
}

/// Saved passwords in a list, beside a count of its own.
public sealed record Remember(IReadOnlyList<ExistingCredential> Credentials, int Hooks) : Intent {
    #region Actions - Routing

    /// A schema fixture is never sent.
    internal override IReadOnlyList<Change> Route(CrestApp app) => throw new NotSupportedException();

    #endregion
}

/// A saved password, maybe.
public sealed record Recall(ExistingCredential? Credential) : Intent {
    #region Actions - Routing

    /// A schema fixture is never sent.
    internal override IReadOnlyList<Change> Route(CrestApp app) => throw new NotSupportedException();

    #endregion
}

/// Nothing secret.
public sealed record Note(string Text) : Intent {
    #region Actions - Routing

    /// A schema fixture is never sent.
    internal override IReadOnlyList<Change> Route(CrestApp app) => throw new NotSupportedException();

    #endregion
}
