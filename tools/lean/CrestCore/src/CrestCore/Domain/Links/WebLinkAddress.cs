using CrestCore.Contracts;

namespace CrestCore.Domain;

internal sealed record WebLinkAddress(string? Scheme, string? Host) {
    #region Static Variables

    /// The longest host a platform-parsed address may report; a longer one is
    /// refused.
    internal const int MaximumHostLength = 1_024;

    #endregion

    #region Variables

    /// Whether the address is a web link: HTTP or HTTPS with a host.
    internal bool IsAccepted => Host is { Length: > 0 and <= MaximumHostLength } && WebScheme.Spelled(Scheme) is not null;

    #endregion

}
