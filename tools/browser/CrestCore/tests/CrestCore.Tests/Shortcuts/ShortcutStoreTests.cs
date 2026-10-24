using System.Text;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// Shortcut choices are device state: the device store keeps them beside the
/// session, carried once from the document an installed release kept, and a
/// change that would take another command's keys waits for the person to
/// confirm it.
public sealed partial class BrowserContractsTests {
    /// One stored row of `device_shortcut`, spelled exactly as the store holds it.
    private sealed record StoredShortcutRow(string Command, string? Key, long Special, long Modifiers);

    private static List<StoredShortcutRow> StoredShortcutRows(string file) {
        Assert.Equal(Sqlite.Ok, Sqlite.sqlite3_open_v2(file, out var connection, Sqlite.OpenReadOnly, null));
        try {
            Assert.Equal(Sqlite.Ok, Sqlite.sqlite3_prepare_v2(connection,
                "SELECT command, key, special, modifiers FROM device_shortcut ORDER BY command", -1, out var statement, 0));
            var rows = new List<StoredShortcutRow>();
            while (Sqlite.sqlite3_step(statement) == Sqlite.Row)
                rows.Add(new(Sqlite.ColumnText(statement, 0), Sqlite.ColumnIsNull(statement, 1) ? null : Sqlite.ColumnText(statement, 1),
                    Sqlite.sqlite3_column_int64(statement, 2), Sqlite.sqlite3_column_int64(statement, 3)));
            Sqlite.sqlite3_finalize(statement);
            return rows;
        } finally {
            Sqlite.sqlite3_close_v2(connection);
        }
    }

    private static Dictionary<ShortcutCommand, ShortcutBinding> Bindings(IReadOnlyList<Change> changes) =>
        Assert.Single(changes.OfType<ShortcutsChanged>()).Bindings.ToDictionary(binding => binding.Command);

    private static KeyCombination Typed(string character, ShortcutModifiers modifiers) => new(character, false, modifiers);

    [Fact]
    public void TheShortcutsAnInstalledReleaseKeptAreAdoptedOnceExactlyAsStored() {
        using var directory = new StorageDirectory();
        // The document as the release's encoder wrote it: a typed key, a named
        // key, a command left without keys, a command this build does not know,
        // and entries that release could not have read back.
        const string Document = """
            {"newTab":{"custom":{"_0":{"key":{"character":"é"},"modifiers":3}}},
            "previousTab":{"custom":{"_0":{"key":{"special":"f20"},"modifiers":36}}},
            "showHistory":{"unassigned":{}},
            "futureCommand":{"custom":{"_0":{"key":{"character":"q"},"modifiers":1}}},
            "findInPage":{"custom":{"_0":{"key":{"character":"ab"},"modifiers":1}}},
            "zoomIn":{"custom":{"_0":{"key":{"special":"hyper"},"modifiers":1}}},
            "zoomOut":{"removed":{}}}
            """;
        {
            var (app, _, _) = DeviceApp(directory);
            using var disposal = app;
            var bindings = Bindings(app.Send(new AdoptShortcuts(Encoding.UTF8.GetBytes(Document))));
            Assert.Equal(Typed("é", ShortcutModifiers.Command | ShortcutModifiers.Option), bindings[ShortcutCommand.NewTab].Keys);
            Assert.True(bindings[ShortcutCommand.NewTab].IsCustomized);
            Assert.Equal(new KeyCombination("f20", true, (ShortcutModifiers)36), bindings[ShortcutCommand.PreviousTab].Keys);
            Assert.Null(bindings[ShortcutCommand.ShowHistory].Keys);
            Assert.Equal(Typed("f", ShortcutModifiers.Command), bindings[ShortcutCommand.FindInPage].Keys);
            Assert.False(bindings[ShortcutCommand.FindInPage].IsCustomized);

            // A later adoption carries nothing more and publishes the bindings the store holds.
            var again = app.Send(new AdoptShortcuts(Encoding.UTF8.GetBytes("""{"newWindow":{"unassigned":{}}}""")));
            Assert.Equal(bindings.Values, Assert.Single(again.OfType<ShortcutsChanged>()).Bindings);
        }

        Assert.Equal([
            new StoredShortcutRow("futureCommand", "q", 0, 1),
            new StoredShortcutRow("newTab", "é", 0, 3),
            new StoredShortcutRow("previousTab", "f20", 1, 36),
            new StoredShortcutRow("showHistory", null, 0, 0)
        ], StoredShortcutRows(directory.File));
        var (relaunched, _, _) = DeviceApp(directory);
        using var relaunchedDisposal = relaunched;
        var restored = Bindings(relaunched.Send(new AdoptShortcuts(null)));
        Assert.Equal(Typed("é", ShortcutModifiers.Command | ShortcutModifiers.Option), restored[ShortcutCommand.NewTab].Keys);
        Assert.Null(restored[ShortcutCommand.ShowHistory].Keys);
        Assert.True(Assert.Single(relaunched.Send(new AdoptShortcuts(null)).OfType<ShortcutsChanged>()).IsCustomized);
    }

    [Fact]
    public void KeysAnotherCommandHoldsWaitForConfirmationAndEveryChangeSurvivesARelaunch() {
        using var directory = new StorageDirectory();
        var find = Typed("f", ShortcutModifiers.Command);
        var chord = Typed("u", ShortcutModifiers.Command | ShortcutModifiers.Shift);
        {
            var (app, _, _) = DeviceApp(directory);
            using var disposal = app;
            app.Send(new AdoptShortcuts(null));
            // Taking a default's keys is refused, naming the command that holds them.
            Assert.Equal([ShortcutCommand.FindInPage], Assert.IsType<ShortcutInUse>(Assert.Throws<Rejected>(() =>
                app.Send(new AssignShortcut(ShortcutCommand.NewTab, find))).Rejection).Commands);
            Assert.Equal(new InvalidShortcut(Typed("t", ShortcutModifiers.None)), Assert.Throws<Rejected>(() =>
                app.Send(new AssignShortcut(ShortcutCommand.NewTab, Typed("t", ShortcutModifiers.None)))).Rejection);
            Assert.Equal(new InvalidShortcut(new KeyCombination("hyper", true, ShortcutModifiers.Command)), Assert.Throws<Rejected>(() =>
                app.Send(new ReassignShortcut(ShortcutCommand.NewTab, new KeyCombination("hyper", true, ShortcutModifiers.Command))))
                .Rejection);

            var assigned = Bindings(app.Send(new AssignShortcut(ShortcutCommand.NewTab, chord)));
            Assert.Equal(chord, assigned[ShortcutCommand.NewTab].Keys);
            Assert.Empty(app.Send(new AssignShortcut(ShortcutCommand.NewTab, chord)).OfType<ShortcutsChanged>());
            Assert.Equal([ShortcutCommand.NewTab], Assert.IsType<ShortcutInUse>(Assert.Throws<Rejected>(() =>
                app.Send(new AssignShortcut(ShortcutCommand.NewWindow, chord))).Rejection).Commands);

            // Confirming takes the keys from their holder, which is left without any.
            var reassigned = Bindings(app.Send(new ReassignShortcut(ShortcutCommand.NewWindow, chord)));
            Assert.Equal(chord, reassigned[ShortcutCommand.NewWindow].Keys);
            Assert.Null(reassigned[ShortcutCommand.NewTab].Keys);
            Assert.True(reassigned[ShortcutCommand.NewTab].IsCustomized);

            // Resetting one command restores its default and nothing else.
            var reset = Bindings(app.Send(new ResetShortcut(ShortcutCommand.NewTab)));
            Assert.Equal(Typed("t", ShortcutModifiers.Command), reset[ShortcutCommand.NewTab].Keys);
            Assert.Equal(chord, reset[ShortcutCommand.NewWindow].Keys);
            Assert.Null(Bindings(app.Send(new UnassignShortcut(ShortcutCommand.ShowHistory)))[ShortcutCommand.ShowHistory].Keys);
        }

        var (relaunched, _, _) = DeviceApp(directory);
        using var relaunchedDisposal = relaunched;
        var restored = Bindings(relaunched.Send(new AdoptShortcuts(null)));
        Assert.Equal(chord, restored[ShortcutCommand.NewWindow].Keys);
        Assert.Null(restored[ShortcutCommand.ShowHistory].Keys);
        Assert.Equal(Typed("t", ShortcutModifiers.Command), restored[ShortcutCommand.NewTab].Keys);

        // Resetting every shortcut forgets them all, on disk too.
        var cleared = Assert.Single(relaunched.Send(new ResetShortcuts()).OfType<ShortcutsChanged>());
        Assert.False(cleared.IsCustomized);
        Assert.All(cleared.Bindings, binding => Assert.False(binding.IsCustomized));
        Assert.Empty(relaunched.Send(new ResetShortcuts()).OfType<ShortcutsChanged>());
    }

    [Fact]
    public void OnlyCommandsTheDefaultEngineOffersHoldKeys() {
        using var app = new CrestApp(new AppConfiguration(null, DevicePlatform.Desktop));
        var reader = Typed("r", ShortcutModifiers.Command | ShortcutModifiers.Option);
        app.Send(new AssignShortcut(ShortcutCommand.ToggleReaderMode, reader));
        // An engine without Reader offers no Reader command, which then neither holds nor loses keys.
        app.RegisterEngine(new EngineRegistration(EngineKind.Chromium, EngineCapability.Required, IsDefault: true), _ => { });
        var offered = Assert.Single(app.Drain().OfType<ShortcutsChanged>()).Bindings.Select(binding => binding.Command).ToArray();
        Assert.DoesNotContain(ShortcutCommand.ToggleReaderMode, offered);
        Assert.Contains(ShortcutCommand.NewTab, offered);
        Assert.Single(app.Send(new AssignShortcut(ShortcutCommand.NewTab, reader)).OfType<ShortcutsChanged>());
    }
}
