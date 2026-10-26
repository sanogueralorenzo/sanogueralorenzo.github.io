using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// The shortcut catalog and the rules for the person's choices: stored
/// names, defaults, conflicts, yielding defaults and which keys make a chord.
public sealed class ShortcutCatalogTests {
    /// Every command name persisted overrides are keyed by, in display order.
    private static readonly string[] Commands = [
        "newWindow", "newBlankWindow", "newTab", "newQuickWindow", "newPrivateWindow", "closeTabOrWindow", "closeWindow",
        "openLocation", "back", "forward", "reloadPage", "stopLoading", "reloadFromOrigin", "toggleSelectedTabPinned",
        "duplicateTab", "reopenClosedTab", "clearUnpinnedTabs", "archiveTab", "previousTab", "nextTab", "mostRecentTab",
        "selectTab1", "selectTab2", "selectTab3", "selectTab4", "selectTab5", "selectTab6", "selectTab7", "selectTab8",
        "selectTab9", "previousSpace", "nextSpace", "selectSpace1", "selectSpace2", "selectSpace3", "selectSpace4",
        "selectSpace5", "selectSpace6", "selectSpace7", "selectSpace8", "selectSpace9", "toggleReaderMode",
        "toggleContentBlocking", "findInPage", "zoomIn", "zoomOut", "actualSize", "copyPageLink", "copyPageLinkAsMarkdown",
        "sharePage", "exportPDF", "saveWebArchive", "printPage", "toggleSidebar", "showHistory", "showArchive",
        "showDownloads", "webInspectorInstructions", "splitWithNextTab", "focusNextSplitCard", "focusPreviousSplitCard",
        "removeTabFromSplit", "separateSplitTabs", "moveSplitCardLeft", "moveSplitCardRight", "toggleDeveloperToolbar",
        "toggleTranslationToolbar", "openFile", "findNext", "findPrevious", "capturePage",
        "mostRecentTabBackward", "clearSiteCookies", "clearSiteCache"
    ];

    private static readonly IReadOnlyList<ShortcutCommand> Offered = ShortcutCommand.All;

    private static ShortcutChord Key(string character, int modifiers) => ShortcutChord.Character(character, modifiers);

    private static ShortcutChord? Default(string command, DevicePlatform platform) =>
        ShortcutCommand.Named(command)?.DefaultShortcut(platform) is { } fallback ? ShortcutChord.Of(fallback.Keys) : null;

    /// Persisted overrides name a special key by its name.
    [Fact]
    public void EverySpecialKeyKeepsTheNameOverridesArePersistedUnder() => Assert.Equal([
        "tab", "leftArrow", "rightArrow", "upArrow", "downArrow", "escape", "returnKey", "delete", "forwardDelete", "home", "end",
        "pageUp", "pageDown", "space", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "f13", "f14",
        "f15", "f16", "f17", "f18", "f19", "f20"
    ], ShortcutSpecialKey.All.Select(key => key.Name));

    [Fact]
    public void EveryCommandKeepsTheNameItsOverridesArePersistedUnder() {
        Assert.Equal(Commands, ShortcutCommand.All.Select(command => command.Name));
        Assert.Same(ShortcutCommand.ShowWebInspector, ShortcutCommand.Named("webInspectorInstructions"));
    }

    /// A focused page sees every other command's keys first, as in other
    /// browsers, so only opening, closing and switching tabs and windows stay
    /// out of its reach.
    [Fact]
    public void OnlyOpeningClosingAndSwitchingTabsAndWindowsAreReservedFromPages() => Assert.Equal([
        "newWindow", "newTab", "newPrivateWindow", "closeTabOrWindow", "closeWindow", "reopenClosedTab", "previousTab", "nextTab",
        "mostRecentTab", "mostRecentTabBackward"
    ], ShortcutCommand.All.Where(command => command.IsReservedFromPages).Select(command => command.Name));

    [Theory]
    [InlineData("desktop")]
    [InlineData("mobile")]
    public void TheDefaultCatalogNeverGivesTwoCommandsOneChord(string platform) {
        var defaults = Commands.Select(command => Default(command, DevicePlatform.Named(platform)!)).OfType<ShortcutChord>().ToArray();
        Assert.Equal(defaults.Length, defaults.Distinct().Count());
        Assert.All(defaults, chord => Assert.True(chord.IsValid));
    }

    [Theory]
    [InlineData("newQuickWindow", "newBlankWindow", "n", ShortcutChord.Command | ShortcutChord.Option)]
    [InlineData("newTab", "newQuickWindow", "n", ShortcutChord.Command | ShortcutChord.Option | ShortcutChord.Shift)]
    [InlineData("newTab", "findNext", "g", ShortcutChord.Command)]
    [InlineData("newTab", "findPrevious", "g", ShortcutChord.Command | ShortcutChord.Shift)]
    [InlineData("newTab", "capturePage", "2", ShortcutChord.Command | ShortcutChord.Shift)]
    public void MacDefaultsAddedLaterYieldToAPersistedCustomChord(string owner, string displaced, string key, int modifiers) {
        var overrides = ShortcutOverrides.Restore([new(owner, Key(key, modifiers)), new("showHistory", null)]);
        var bindings = overrides.Bindings(Offered, DevicePlatform.Desktop).ToDictionary(binding => binding.Command.Name);
        Assert.Equal(Key(key, modifiers).Keys, bindings[owner].Keys);
        Assert.Null(bindings[displaced].Keys);
        Assert.False(bindings[displaced].IsCustomized);
        Assert.Null(bindings["showHistory"].Keys);
        Assert.True(bindings["showHistory"].IsCustomized);
        Assert.Equal(Key(key, modifiers), overrides.Resetting(ShortcutCommand.Named(owner)!)
            .Effective(ShortcutCommand.Named(displaced)!, Offered, DevicePlatform.Desktop));
    }

    /// Control-Shift-Tab arrives after people could have customised shortcuts,
    /// so it stays unbound while a person holds its keys.
    [Fact]
    public void TheBackwardMostRecentTabDefaultYieldsToAPersistedCustomChord() {
        var keys = ShortcutCommand.MostRecentTabBackward.DefaultShortcut(DevicePlatform.Desktop)!.Keys;
        var overrides = ShortcutOverrides.Restore([new("newTab", ShortcutChord.Of(keys))]);
        var bindings = overrides.Bindings(Offered, DevicePlatform.Desktop).ToDictionary(binding => binding.Command.Name);
        Assert.Null(bindings["mostRecentTabBackward"].Keys);
        Assert.NotNull(ShortcutCommand.MostRecentTabBackward.DefaultShortcut(DevicePlatform.Mobile));
    }
}
