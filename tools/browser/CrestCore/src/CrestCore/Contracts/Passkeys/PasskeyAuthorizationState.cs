namespace CrestCore.Contracts;

/// The platform's browser-passkey authorization for Crest, and where passkey
/// access stands once the build and the device allow it. A state travels as
/// its index in `All`, so `All` is append-only.
public sealed class PasskeyAuthorizationState {
    #region Static Variables

    public static readonly PasskeyAuthorizationState Authorized = new(name: "authorized", accessStatus: PasskeyAccessStatus.Authorized);
    public static readonly PasskeyAuthorizationState Denied = new(name: "denied", accessStatus: PasskeyAccessStatus.Denied);
    public static readonly PasskeyAuthorizationState NotDetermined = new(name: "notDetermined",
        accessStatus: PasskeyAccessStatus.NotDetermined);

    public static IReadOnlyList<PasskeyAuthorizationState> All { get; } = [Authorized, Denied, NotDetermined];

    #endregion

    #region Variables

    public string Name { get; }

    /// Where passkey access stands under this authorization, once the build
    /// has the managed capability and the device has passkeys set up.
    public PasskeyAccessStatus AccessStatus { get; }

    #endregion

    #region Constructors

    private PasskeyAuthorizationState(string name, PasskeyAccessStatus accessStatus) {
        Name = name;
        AccessStatus = accessStatus;
    }

    #endregion

    #region Actions - Lookup

    public static PasskeyAuthorizationState? Named(string? name) => All.FirstOrDefault(state => state.Name == name);

    #endregion
}
