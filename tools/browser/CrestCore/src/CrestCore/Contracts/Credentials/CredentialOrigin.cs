namespace CrestCore.Contracts;

/// The canonical HTTP(S) origin a credential belongs to. The platform
/// canonicalizes scheme, host and default port before it reaches the core, so
/// equality is exact member equality. The credential rules refuse an origin
/// that is not `IsValid`.
public sealed record CredentialOrigin(string Scheme, string Host, int Port) {
    #region Variables

    public const int MaximumHostLength = 1_024;

    public bool IsValid => WebScheme.Named(Scheme) is not null && !string.IsNullOrEmpty(Host) && Host.Length <= MaximumHostLength
        && Port is >= 1 and <= 65_535;

    public bool IsSecure => WebScheme.Named(Scheme)?.IsSecure == true;

    /// The origin as an address spells it: its scheme and host, an IPv6 host
    /// in brackets, and its port only where it is not the scheme's default.
    public string Spelling {
        get {
            string host = Host.Contains(':', StringComparison.Ordinal) ? $"[{Host}]" : Host;
            return WebScheme.Named(Scheme)?.DefaultPort == Port ? $"{Scheme}://{host}" : $"{Scheme}://{host}:{Port}";
        }
    }

    #endregion

    #region Actions - Capture

    /// Whether a frame at this origin under a top-level page at
    /// `topLevelOrigin` may capture and be offered credentials: both must be
    /// secure.
    internal bool IsSecureUnder(CredentialOrigin topLevelOrigin) {
        ArgumentNullException.ThrowIfNull(topLevelOrigin);
        return Validated().IsSecure && topLevelOrigin.Validated().IsSecure;
    }

    /// This origin, or the refusal of one that is not `IsValid`.
    internal CredentialOrigin Validated() => IsValid ? this : throw new Rejected(new InvalidCredentialOrigin());

    #endregion
}
