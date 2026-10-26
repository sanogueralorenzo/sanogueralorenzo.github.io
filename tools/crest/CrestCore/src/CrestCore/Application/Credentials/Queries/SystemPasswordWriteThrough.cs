using CrestCore.Application;

namespace CrestCore.Contracts;

/// Whether this launch can offer saved passwords to the system's Passwords app.
/// `SupportsSystemPasswordSaving` says the operating system has the API that
/// saves one; `IsLaunchIsolated` says this launch keeps away from the person's
/// own stores. Write-through is a mobile feature. An isolated launch never
/// reaches the person's system password store, whatever the build can do.
public sealed record SystemPasswordWriteThrough(bool IsMobilePlatform, bool SupportsSystemPasswordSaving,
    bool HasManagedBrowserCapability, bool IsLaunchIsolated) : Query<SystemPasswordWriteThroughSupport> {
    #region Variables

    internal SystemPasswordWriteThroughAvailability Availability {
        get {
            if (!IsMobilePlatform) return SystemPasswordWriteThroughAvailability.UnsupportedPlatform;
            if (IsLaunchIsolated) return SystemPasswordWriteThroughAvailability.IsolatedLaunch;
            if (!SupportsSystemPasswordSaving) return SystemPasswordWriteThroughAvailability.SystemVersionRequired;
            return HasManagedBrowserCapability
                ? SystemPasswordWriteThroughAvailability.Available
                : SystemPasswordWriteThroughAvailability.ManagedBrowserCapabilityRequired;
        }
    }

    #endregion

    #region Actions - Answering

    internal override SystemPasswordWriteThroughSupport Answer(CrestApp app) {
        return new(Availability);
    }

    #endregion
}
