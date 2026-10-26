using CrestCore.Application;

namespace CrestCore.Contracts;

/// Whether websites in Crest can use the system's passkey providers, from the
/// platform's build, device and authorization facts.
public sealed record PasskeyAccess(bool HasManagedCapability, PasskeyDeviceConfiguration DeviceConfiguration,
    PasskeyAuthorizationState AuthorizationState) : Query<PasskeyAccessVerdict> {
    #region Variables

    /// The managed capability comes first, then device setup, then consent.
    internal PasskeyAccessStatus Status {
        get {
            ArgumentNullException.ThrowIfNull(DeviceConfiguration);
            ArgumentNullException.ThrowIfNull(AuthorizationState);
            if (!HasManagedCapability) return PasskeyAccessStatus.ManagedCapabilityRequired;
            if (DeviceConfiguration.RulesOutPasskeys) return PasskeyAccessStatus.DeviceNotConfigured;
            return AuthorizationState.AccessStatus;
        }
    }

    #endregion

    #region Actions - Answering

    internal override PasskeyAccessVerdict Answer(CrestApp app) {
        return new(Status);
    }

    #endregion
}
