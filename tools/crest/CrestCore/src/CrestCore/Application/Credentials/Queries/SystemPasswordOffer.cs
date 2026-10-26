using CrestCore.Application;

namespace CrestCore.Contracts;

/// Whether a save prompt goes on to offer the password to the system's
/// Passwords app: only when the Space opted in, the launch can, and the window
/// is not private.
public sealed record SystemPasswordOffer(bool SpaceOffersSystemPasswords, SystemPasswordWriteThroughAvailability Availability,
    bool IsPrivateBrowsing) : Query<SystemPasswordOfferDecision> {
    #region Variables

    /// Offered only after the Space opts in, when available, and never from a
    /// private window.
    internal bool Offers =>
        SpaceOffersSystemPasswords && Availability == SystemPasswordWriteThroughAvailability.Available && !IsPrivateBrowsing;

    #endregion

    #region Actions - Answering

    internal override SystemPasswordOfferDecision Answer(CrestApp app) {
        return new(Offers);
    }

    #endregion
}
