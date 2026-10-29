using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    [Fact]
    public void FixedShortcutsFollowTheCommandsTheDefaultEngineOffers() {
        using var app = new CrestApp(new AppConfiguration(null, DevicePlatform.Desktop));
        var bindings = app.Query(new GetShortcuts()).Bindings.ToDictionary(binding => binding.Command);
        Assert.Equal(new KeyCombination("t", false, ShortcutModifiers.Command), bindings[ShortcutCommand.NewTab].Keys);
        app.RegisterEngine(new EngineRegistration(EngineCapability.Required), _ => { });
        var offered = app.Query(new GetShortcuts()).Bindings.Select(binding => binding.Command).ToArray();
        Assert.DoesNotContain(ShortcutCommand.ToggleReaderMode, offered);
        Assert.Contains(ShortcutCommand.NewTab, offered);
    }
}
