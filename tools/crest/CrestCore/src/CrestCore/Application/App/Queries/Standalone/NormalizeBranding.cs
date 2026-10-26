using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// `Branding` with the core's range rules applied, as a Space keeps it. It
/// reads no state, so a host may ask it without an app.
public sealed record NormalizeBranding(SpaceBranding Branding) : StandaloneQuery<NormalizedBranding> {
    #region Actions - Answering

    internal override NormalizedBranding Answer(StandaloneContext context) => new(SpaceBranding.Normalized(Branding));

    #endregion
}
