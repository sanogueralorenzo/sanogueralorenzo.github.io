using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed class PasskeyAccessTests {
    [Fact]
    public void PasskeyAccessChecksTheCapabilityThenTheDeviceThenConsent() {
        Assert.Equal(PasskeyAccessStatus.ManagedCapabilityRequired,
            new PasskeyAccess(false, PasskeyDeviceConfiguration.NotConfigured, PasskeyAuthorizationState.Authorized).Status);
        Assert.Equal(PasskeyAccessStatus.DeviceNotConfigured,
            new PasskeyAccess(true, PasskeyDeviceConfiguration.NotConfigured, PasskeyAuthorizationState.Authorized).Status);
        Assert.Equal(PasskeyAccessStatus.Authorized,
            new PasskeyAccess(true, PasskeyDeviceConfiguration.Unknown, PasskeyAuthorizationState.Authorized).Status);
        Assert.Equal(PasskeyAccessStatus.Denied,
            new PasskeyAccess(true, PasskeyDeviceConfiguration.Configured, PasskeyAuthorizationState.Denied).Status);
        Assert.Equal(PasskeyAccessStatus.NotDetermined,
            new PasskeyAccess(true, PasskeyDeviceConfiguration.Configured, PasskeyAuthorizationState.NotDetermined).Status);
    }
}
