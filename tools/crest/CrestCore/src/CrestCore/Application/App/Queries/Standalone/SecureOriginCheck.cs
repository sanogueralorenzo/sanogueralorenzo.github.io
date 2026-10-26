using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Whether a site may use a capability that needs a secure origin, such as
/// location or hosted notifications, at all.
public sealed record SecureOriginCheck(SiteOrigin Origin) : StandaloneQuery<SecureOriginVerdict> {
    #region Actions - Answering

    internal override SecureOriginVerdict Answer(StandaloneContext context) => new(Origin.IsSecureContext);

    #endregion
}
