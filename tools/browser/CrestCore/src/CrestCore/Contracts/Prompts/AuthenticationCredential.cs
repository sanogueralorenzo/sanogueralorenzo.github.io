namespace CrestCore.Contracts;

/// A user name and password for an HTTP challenge. It describes itself without
/// the password, so no log or failure message can carry it.
public sealed record AuthenticationCredential(string Username, string Password) {
    #region Actions - Description

    public override string ToString() => $"AuthenticationCredential {{ Username = {Username} }}";

    #endregion
}
