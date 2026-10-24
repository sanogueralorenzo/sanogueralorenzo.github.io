using CrestCore.Application;

namespace CrestCore.Contracts;

/// Whether another app, a drop, a Peek, a popup or a menu may hand Crest an
/// address as a web link: HTTP or HTTPS with a host. The address arrives as
/// the scheme and host the platform's own parser reported. Everything else is
/// refused, so a page or another app cannot steer Crest at local paths or
/// other schemes.
public sealed record ExternalWebLink(string? Scheme, string? Host) : StandaloneQuery<ExternalAddressVerdict> {
    #region Static Variables

    /// The longest host a platform-parsed address may report; a longer one is
    /// refused.
    internal const int MaximumHostLength = 1_024;

    #endregion

    #region Variables

    /// Whether the address is a web link: HTTP or HTTPS with a host.
    internal bool IsAccepted => Host is { Length: > 0 and <= MaximumHostLength } && WebScheme.Spelled(Scheme) is not null;

    #endregion

    #region Actions - Answering

    internal override ExternalAddressVerdict Answer(StandaloneContext context) => new(IsAccepted);

    #endregion
}
