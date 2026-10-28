using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class LaunchIsolationTests {
    private static readonly string[] FixtureFlags = [
        "testRuntime", "previewRuntime", "isolatedSession", "isolatedCloudSync", "resetSession", "showcase",
        "performanceHarness", "updateTestFeed"
    ];

    /// A launch environment with the named flags on.
    private static LaunchEnvironment Environment(params string[] enabled) {
        bool On(string flag) => enabled.Contains(flag);
        return new(On("testRuntime"), On("previewRuntime"), On("isolatedSession"), On("namedProfile"), On("isolatedCloudSync"),
            On("resetSession"), On("showcase"),
            On("performanceHarness"), On("updateTestFeed"));
    }

    /// The plan the core answers before any session exists.
    private static LaunchDecision Plan(LaunchEnvironment environment) =>
        new StandaloneAnswers().Query(new LaunchIsolation(environment));

    [Fact]
    public void EveryTestAndFixtureLaunchStaysOutOfTheInstalledProfile() {
        foreach (var flag in FixtureFlags)
            Assert.True(Plan(Environment(flag)).RequiresIsolation, flag);
        var installed = Plan(Environment());
        Assert.False(installed.RequiresIsolation);
        Assert.False(installed.UsesEphemeralProfileStorage);
        // A profile name alone never isolates; it only keeps an isolated launch's storage.
        Assert.False(Plan(Environment("namedProfile")).RequiresIsolation);
    }

    [Fact]
    public void OnlyANamedIsolatedProfileKeepsPersistentWebStorage() {
        Assert.True(Plan(Environment("isolatedSession")).UsesEphemeralProfileStorage);
        Assert.False(Plan(Environment("isolatedSession", "namedProfile")).UsesEphemeralProfileStorage);
    }

    [Fact]
    public void OnlyTheTestRuntimeSuppressesInstalledApplicationUI() {
        Assert.False(Plan(Environment("testRuntime")).PresentsInstalledApplicationUI);
        Assert.True(Plan(Environment("isolatedSession")).PresentsInstalledApplicationUI);
        Assert.True(Plan(Environment("previewRuntime")).PresentsInstalledApplicationUI);
    }

}
