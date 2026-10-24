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
        "toggleTranslationToolbar", "openFile", "findNext", "findPrevious", "capturePage"
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

    /// Every command has one menu item, so a platform whose chords run through
    /// its menus runs each of them, and a new command cannot go missing.
    [Fact]
    public void EveryCommandSitsInExactlyOneMenuGroup() {
        var groups = ShortcutMenu.All.SelectMany(menu => menu.Groups).ToArray();
        var placed = groups.SelectMany(group => group).ToArray();
        Assert.Equal(placed.Length, placed.Distinct().Count());
        Assert.Empty(ShortcutCommand.All.Except(placed));
        Assert.DoesNotContain(groups, group => group.Count == 0);
    }

    /// A focused page sees every other command's keys first, as in other
    /// browsers, so only opening, closing and switching tabs and windows stay
    /// out of its reach.
    [Fact]
    public void OnlyOpeningClosingAndSwitchingTabsAndWindowsAreReservedFromPages() => Assert.Equal([
        "newWindow", "newTab", "newPrivateWindow", "closeTabOrWindow", "closeWindow", "reopenClosedTab", "previousTab", "nextTab",
        "mostRecentTab"
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
        Assert.Equal(Key("n", ShortcutChord.Command | ShortcutChord.Option), Default("newQuickWindow", DevicePlatform.Mobile));
        Assert.Null(Default("duplicateTab", DevicePlatform.Desktop));
    }

    [Fact]
    public void AConflictNamesOnlyOtherHoldersAndChangesNothingUntilReassigned() {
        var chord = Key("u", ShortcutChord.Command | ShortcutChord.Shift);
        var first = ShortcutOverrides.None.Assigning(ShortcutCommand.NewTab, chord, Offered, DevicePlatform.Desktop);
        Assert.True(first.Assigning(ShortcutCommand.NewTab, chord, Offered, DevicePlatform.Desktop).SameAs(first));

        var refused = Assert.Throws<Rejected>(() => first.Assigning(ShortcutCommand.NewWindow, chord, Offered, DevicePlatform.Desktop));
        Assert.Equal([ShortcutCommand.NewTab], Assert.IsType<ShortcutInUse>(refused.Rejection).Commands);

        var replaced = first.Reassigning(ShortcutCommand.NewWindow, chord, Offered, DevicePlatform.Desktop);
        // The displaced command had a default, so it is kept as left without keys.
        Assert.Null(replaced.Effective(ShortcutCommand.NewTab, Offered, DevicePlatform.Desktop));
        Assert.Contains(new KeyValuePair<string, ShortcutChord?>("newTab", null), replaced.Chords);
        Assert.Equal(chord, replaced.Effective(ShortcutCommand.NewWindow, Offered, DevicePlatform.Desktop));
    }

    [Fact]
    public void TakingADefaultsKeysNamesItsHolderAndADefaultValueIsNoChoice() {
        var find = Key("f", ShortcutChord.Command);
        Assert.Equal([ShortcutCommand.FindInPage], Assert.IsType<ShortcutInUse>(Assert.Throws<Rejected>(() =>
            ShortcutOverrides.None.Assigning(ShortcutCommand.NewTab, find, Offered, DevicePlatform.Desktop)).Rejection).Commands);
        var moved = ShortcutOverrides.Restore([new("newTab", Key("y", ShortcutChord.Option))]);
        Assert.False(moved.Assigning(ShortcutCommand.NewTab, Key("t", ShortcutChord.Command), Offered, DevicePlatform.Desktop)
            .IsCustomized);
        Assert.False(ShortcutOverrides.None.Unassigning(ShortcutCommand.DuplicateTab, DevicePlatform.Desktop).IsCustomized);
        Assert.Equal([new KeyValuePair<string, ShortcutChord?>("showHistory", null)],
            ShortcutOverrides.None.Unassigning(ShortcutCommand.ShowHistory, DevicePlatform.Desktop).Chords);
        Assert.True(moved.Resetting(ShortcutCommand.NewTab).SameAs(ShortcutOverrides.None));
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

    [Fact]
    public void OnlyOfferedCommandsCanHoldOrLoseAChord() {
        var reader = Key("r", ShortcutChord.Command | ShortcutChord.Option);
        var offered = ShortcutCommand.All.Where(command => command != ShortcutCommand.ToggleReaderMode).ToArray();
        var hidden = ShortcutOverrides.Restore([new("toggleReaderMode", reader)]);
        var taken = hidden.Assigning(ShortcutCommand.NewTab, reader, offered, DevicePlatform.Desktop);
        Assert.Contains(new KeyValuePair<string, ShortcutChord?>("toggleReaderMode", reader), taken.Chords);
        Assert.Equal([ShortcutCommand.ToggleReaderMode], Assert.IsType<ShortcutInUse>(Assert.Throws<Rejected>(() =>
            hidden.Assigning(ShortcutCommand.NewTab, reader, Offered, DevicePlatform.Desktop)).Rejection).Commands);
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
}
