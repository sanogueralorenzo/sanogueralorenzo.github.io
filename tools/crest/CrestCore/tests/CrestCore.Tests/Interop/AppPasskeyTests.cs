using CrestCore.Contracts;
using CrestCore.Native;

using Xunit;

namespace CrestCore.Tests;

public sealed class AppPasskeyTests {
    [Fact]
    public void PasskeyQueriesAnswerThroughTheBoundary() {
        using var app = new AppClient();
        Assert.Equal(PasskeyAccessStatus.DeviceNotConfigured, app.Ask(new PasskeyAccess(true, PasskeyDeviceConfiguration.NotConfigured,
            PasskeyAuthorizationState.Authorized), ContractCodec.ReadPasskeyAccessVerdict).Status);
    }
}
