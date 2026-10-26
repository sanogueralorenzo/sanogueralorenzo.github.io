using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// The shortcut catalog, platform defaults and which keys make a chord.
public sealed class ShortcutCatalogTests {
    /// Every command name persisted overrides are keyed by, in display order.
    private static readonly string[] Commands = [
        "newWindow", "newBlankWindow", "newTab", "newPrivateWindow", "closeTabOrWindow", "closeWindow",
        "openLocation", "back", "forward", "reloadPage", "stopLoading", "reloadFromOrigin", "toggleSelectedTabPinned",
        "duplicateTab", "reopenClosedTab", "clearUnpinnedTabs", "archiveTab", "previousTab", "nextTab", "mostRecentTab", "mostRecentTabBackward",
        "selectTab1", "selectTab2", "selectTab3", "selectTab4", "selectTab5", "selectTab6", "selectTab7", "selectTab8",
        "selectTab9", "previousSpace", "nextSpace", "selectSpace1", "selectSpace2", "selectSpace3", "selectSpace4",
        "selectSpace5", "selectSpace6", "selectSpace7", "selectSpace8", "selectSpace9", "toggleReaderMode",
        "toggleContentBlocking", "findInPage", "zoomIn", "zoomOut", "actualSize", "copyPageLink", "copyPageLinkAsMarkdown",
        "sharePage", "exportPDF", "saveWebArchive", "printPage", "toggleSidebar", "showHistory", "showArchive",
        "showDownloads", "webInspectorInstructions", "splitWithNextTab", "focusNextSplitCard", "focusPreviousSplitCard",
        "removeTabFromSplit", "separateSplitTabs", "moveSplitCardLeft", "moveSplitCardRight", "toggleDeveloperToolbar",
        "translatePage", "openFile", "findNext", "findPrevious"
    ];

    private static ShortcutChord Key(string character, int modifiers) => ShortcutChord.Character(character, modifiers);

    private static ShortcutChord? Default(string command, DevicePlatform platform) =>
        ShortcutCommand.Named(command)?.DefaultShortcut(platform) is { } fallback ? ShortcutChord.Of(fallback.Keys) : null;

    /// Native input names a special key by its name.
    [Fact]
    public void EverySpecialKeyKeepsItsNativeName() => Assert.Equal([
        "tab", "leftArrow", "rightArrow", "upArrow", "downArrow", "escape", "returnKey", "delete", "forwardDelete", "home", "end",
        "pageUp", "pageDown", "space", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "f13", "f14",
        "f15", "f16", "f17", "f18", "f19", "f20"
    ], ShortcutSpecialKey.All.Select(key => key.Name));

    [Fact]
    public void EveryCommandKeepsItsPublishedName() {
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

    [Fact]
    public void NumberedCommandsDefaultToCommandAndControlDigitsAndTheMacAddsABlankWindow() {
        Assert.Equal(Key("3", ShortcutChord.Command), Default("selectTab3", DevicePlatform.Mobile));
        Assert.Equal(Key("9", ShortcutChord.Control), Default("selectSpace9", DevicePlatform.Desktop));
        Assert.Null(Default("selectTab10", DevicePlatform.Desktop));
        Assert.Equal(Key("n", ShortcutChord.Command | ShortcutChord.Option), Default("newBlankWindow", DevicePlatform.Desktop));
        Assert.Null(Default("newBlankWindow", DevicePlatform.Mobile));
        Assert.Null(Default("duplicateTab", DevicePlatform.Desktop));
        Assert.Null(Default("toggleSidebar", DevicePlatform.Desktop));
        Assert.Equal(Key("b", ShortcutChord.Command), Default("toggleSidebar", DevicePlatform.Mobile));
    }

    [Fact]
    public void OnlyKeysWithASupportedModifierAndANameMakeAChord() {
        Assert.Null(ShortcutChord.Usable(new("t", false, ShortcutModifiers.None)));
        Assert.Null(ShortcutChord.Usable(new("t", false, (ShortcutModifiers)(1 << 5))));
        Assert.Null(ShortcutChord.Usable(new("hyper", true, ShortcutModifiers.Command)));
        Assert.Null(ShortcutChord.Usable(new("", false, ShortcutModifiers.Command)));
        Assert.Equal(Key("t", ShortcutChord.Command), ShortcutChord.Usable(new("t", false, ShortcutModifiers.Command)));
        // The decomposed and composed spellings of a key are one chord.
        Assert.Equal(ShortcutChord.Usable(new("e\u0301", false, ShortcutModifiers.Command)),
            ShortcutChord.Usable(new("\u00e9", false, ShortcutModifiers.Command)));
    }

}
