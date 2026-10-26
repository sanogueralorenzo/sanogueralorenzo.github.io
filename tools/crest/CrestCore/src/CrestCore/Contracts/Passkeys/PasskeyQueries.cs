namespace CrestCore.Contracts;

/// Where passkey access for websites stands.
public sealed record PasskeyAccessVerdict(PasskeyAccessStatus Status);

/// Whether the save prompt offers the password to the system's Passwords app.
public sealed record SystemPasswordOfferDecision(bool Offers);

/// Whether Crest may offer a saved password to the system's Passwords app.
public enum SystemPasswordWriteThroughAvailability {
    Available,
    UnsupportedPlatform,
    IsolatedLaunch,
    SystemVersionRequired,
    ManagedBrowserCapabilityRequired
}

/// Whether this launch may offer saved passwords to the system's Passwords app,
/// or why not.
public sealed record SystemPasswordWriteThroughSupport(SystemPasswordWriteThroughAvailability Availability);
