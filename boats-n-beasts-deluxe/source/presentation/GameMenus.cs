using Godot;
using BoatsNBeasts.Core;
using V2 = System.Numerics.Vector2;
namespace BoatsNBeasts;

public partial class Game : Node2D
{
    StyleBoxFlat Box(Color bg, int radius = 14, Color? border = null)
    {
        var s = new StyleBoxFlat { BgColor = bg, CornerRadiusTopLeft = radius, CornerRadiusTopRight = radius, CornerRadiusBottomLeft = radius, CornerRadiusBottomRight = radius, ContentMarginLeft = 22, ContentMarginRight = 22, ContentMarginTop = 15, ContentMarginBottom = 15 };
        if (border != null) { s.BorderColor = border.Value; s.SetBorderWidthAll(2); } return s;
    }
    Label Label(string text, int size = 22, bool heading = false, Color? color = null)
    {
        var l = new Label { Text = text, AutowrapMode = TextServer.AutowrapMode.WordSmart };
        l.AddThemeFontOverride("font", heading ? titleFont : bodyFont); l.AddThemeFontSizeOverride("font_size", size); l.AddThemeColorOverride("font_color", color ?? NauticalPalette.Cream); return l;
    }
    Button Button(string text, Action action, bool primary = false, bool disabled = false, bool purchase = false)
    {
        var b = new Button { Text = text, CustomMinimumSize = new(0, 46), Disabled = disabled, MouseDefaultCursorShape = Control.CursorShape.PointingHand };
        b.AddThemeFontOverride("font", bodyFont); b.AddThemeFontSizeOverride("font_size", 19);
        b.AddThemeColorOverride("font_color", primary ? NauticalPalette.Navy : NauticalPalette.Cream); b.AddThemeColorOverride("font_hover_color", NauticalPalette.Navy); b.AddThemeColorOverride("font_focus_color", primary ? NauticalPalette.Navy : NauticalPalette.Cream); b.AddThemeColorOverride("font_pressed_color", NauticalPalette.Navy); b.AddThemeColorOverride("font_disabled_color", new Color(NauticalPalette.Cream, .34f));
        b.AddThemeStyleboxOverride("normal", Box(primary ? NauticalPalette.Aqua : new Color("102e43"), 9, primary ? null : new Color("345064")));
        b.AddThemeStyleboxOverride("hover", Box(NauticalPalette.Aqua, 9)); b.AddThemeStyleboxOverride("pressed", Box(NauticalPalette.Aqua, 9)); b.AddThemeStyleboxOverride("focus", Box(new Color(0, 0, 0, 0), 9, NauticalPalette.Aqua)); b.AddThemeStyleboxOverride("disabled", Box(new Color("102838"), 9));
        if (purchase)
        {
            b.AddThemeColorOverride("font_color", new Color("edc77e"));
            b.AddThemeStyleboxOverride("normal", Box(new Color("102e43"), 9, new Color("8c784e")));
        }
        Tween? hover = null;
        void AnimateHover(float scale)
        {
            if (b.Disabled) return;
            hover?.Kill(); b.PivotOffset = b.Size / 2;
            hover = b.CreateTween(); hover.TweenProperty(b, "scale", Vector2.One * scale, .12);
        }
        b.MouseEntered += () => AnimateHover(1.015f);
        b.MouseExited += () => AnimateHover(1);
        b.Pressed += () => { action(); }; return b;
    }
    VBoxContainer Panel(float width, string heading, string detail, bool besideBoat = false)
    {
        var center = new CenterContainer(); center.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect); menuRoot.AddChild(center);
        if (besideBoat) center.AnchorRight = .52f;
        var panel = new PanelContainer { CustomMinimumSize = new(width, 0) }; panel.AddThemeStyleboxOverride("panel", Box(new Color("102f39"), 12, new Color("ac8b56"))); center.AddChild(panel);
        var column = new VBoxContainer(); column.AddThemeConstantOverride("separation", 14); panel.AddChild(column);
        column.AddChild(Label(heading, 36, true));
        column.AddChild(Label(detail, 18));
        return column;
    }
    MenuButton MenuAction(string text, MenuGlyph glyph, Action action, bool primary = false)
    {
        var button = new MenuButton { Text = text, Glyph = glyph, Primary = primary };
        button.AddThemeFontOverride("font", bodyFont);
        button.Pressed += action;
        return button;
    }
    void BuildMenu()
    {
        if (menuRoot != null) { layer.RemoveChild(menuRoot); menuRoot.QueueFree(); }
        menuRoot = new Control { MouseFilter = Control.MouseFilterEnum.Ignore }; menuRoot.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect); layer.AddChild(menuRoot);
        shownMode = Run.Mode;
        if (controls) { ControlsMenu(); FocusFirst(menuRoot); return; }
        if (title)
        {
            if (choosingBoat)
            {
                if (daily is { } challenge) DailyMenu(challenge);
                else BoatMenu();
                return;
            }
            if (sailLocker) { SailLockerMenu(); return; }
            if (journal) JournalMenu();
            else TitleMenu();
            FocusFirst(menuRoot);
            return;
        }
        if (Run.Mode == VoyageMode.Sailing) return;
        departingMenu?.Hide();
        var shade = new ColorRect { Color = new(0.015f, .06f, .16f, .66f), MouseFilter = Control.MouseFilterEnum.Stop }; shade.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect); menuRoot.AddChild(shade);
        VBoxContainer col;
        switch (Run.Mode)
        {
            case VoyageMode.Paused:
                col = Panel(520, "At anchor", Run.BossSlain ? "The sea is calm. Explore at your own pace." : "The voyage is paused.");
                col.AddChild(MenuAction("Resume voyage", MenuGlyph.Sail, () => { Run.Mode = beforePause; BuildMenu(); }, true));
                col.AddChild(MenuAction("Captain’s handbook", MenuGlyph.Book, () => { controls = true; BuildMenu(); }));
                AddMuteButton(col);
                col.AddChild(MenuAction("Return to harbor", MenuGlyph.Harbor, BackToTitle)); break;
            case VoyageMode.Upgrade: UpgradeMenu(); break;
            case VoyageMode.Defeat:
                Record(); col = Panel(570, "Lost to the deep", VoyageSummary());
                col.AddChild(Button("Sail again", Start, true));
                col.AddChild(Button(daily.HasValue ? "Return to harbor" : "Choose another boat", BackToTitle)); break;
            case VoyageMode.Victory:
                Record(); col = Panel(570, "Crownclaw defeated", VoyageSummary());
                col.AddChild(daily.HasValue ? Button("Sail again", Start, true)
                    : Button("Keep exploring", () => { Run.Mode = VoyageMode.Sailing; BuildMenu(); }, true));
                col.AddChild(Button("A new voyage", BackToTitle)); break;
        }
        FocusFirst(menuRoot);
    }
    bool FocusFirst(Node root)
    {
        foreach (var child in root.GetChildren()) { if (child is Button { Disabled: false } b) { b.GrabFocus(); return true; } if (FocusFirst(child)) return true; }
        return false;
    }
    void TitleMenu()
    {
        var scrim = new TextureRect { MouseFilter = Control.MouseFilterEnum.Ignore, ExpandMode = TextureRect.ExpandModeEnum.IgnoreSize };
        scrim.Texture = new GradientTexture2D
        {
            Gradient = new Gradient
            {
                Offsets = [0, .40f, .75f],
                Colors = [new Color("061e29ef"), new Color("061e2987"), new Color("061e2900")]
            },
            FillFrom = Vector2.Zero,
            FillTo = Vector2.Right
        };
        scrim.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        menuRoot.AddChild(scrim);

        var column = new VBoxContainer();
        column.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.CenterLeft);
        column.OffsetLeft = 76;
        column.OffsetRight = 475;
        column.OffsetTop = -258;
        column.AddThemeConstantOverride("separation", 11);
        menuRoot.AddChild(column);
        column.AddChild(Label("Boats ’n’\nBeasts", 79, true));
        column.AddChild(Label("DELUXE", 17, false, NauticalPalette.Gold));
        column.AddChild(new Control { CustomMinimumSize = new(0, 8), MouseFilter = Control.MouseFilterEnum.Ignore });
        column.AddChild(MenuAction("Chart a voyage", MenuGlyph.Sail, () => { choosingBoat = true; BuildMenu(); }, true));
        column.AddChild(MenuAction("Daily challenge", MenuGlyph.Chart, OpenDaily));
        column.AddChild(MenuAction("Captain’s log", MenuGlyph.Book, () => { journal = true; BuildMenu(); }));
        column.AddChild(MenuAction("How to sail", MenuGlyph.Chart, () => { controls = true; BuildMenu(); }));
    }

    void BoatMenu()
    {
        var col = Panel(630, "Chart a voyage", "Choose a boat and a charter.");
        var choices = new HBoxContainer(); choices.AddThemeConstantOverride("separation", 8); col.AddChild(choices);
        foreach (var boat in Enum.GetValues<BoatKind>())
        {
            choices.AddChild(Button(BoatSpec.For(boat).Name, () =>
            {
                selectedBoat = boat;
                PreviewRun(selectedSeed, selectedBoat, selectedCharter);
                BuildMenu();
            }, selectedBoat == boat));
        }

        var spec = BoatSpec.For(selectedBoat);
        col.AddChild(Label($"{spec.Hull * Run.Rules.HullFactor:0} hull  ·  {spec.Speed:0} sailing speed", 16, false, NauticalPalette.Gold));
        col.AddChild(Label($"{spec.Maneuver} · {spec.ManeuverSeconds}s recharge", 23, true));
        col.AddChild(Label(spec.Description, 18));

        var charters = new HBoxContainer(); charters.AddThemeConstantOverride("separation", 8); col.AddChild(charters);
        foreach (var charter in Enum.GetValues<Charter>())
        {
            if (!log.Owns(charter)) continue;
            charters.AddChild(Button(CharterRules.For(charter).Name, () =>
            {
                selectedCharter = charter;
                PreviewRun(selectedSeed, selectedBoat, selectedCharter);
                BuildMenu();
            }, selectedCharter == charter));
        }
        col.AddChild(Label(Run.Rules.Description, 17));
        AddDepartureButtons(col);
    }

    void AddDepartureButtons(VBoxContainer col)
    {

        var actions = new HBoxContainer(); actions.AddThemeConstantOverride("separation", 8); col.AddChild(actions);
        actions.AddChild(Button("Back", () =>
        {
            choosingBoat = false;
            RestoreOpenChart();
            BuildMenu();
        }));
        var sail = Button("Set sail", Start, true);
        sail.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill;
        actions.AddChild(sail);
        sail.GrabFocus();
    }

    void JournalMenu()
    {
        var col = Panel(640, "Captain’s log",
            $"{log.Silver} silver  ·  {log.Wins} wins in {log.Voyages} voyages\nBest haul {log.BestKills} beasts  ·  Longest chain {log.BestChain}\nDaily clears {log.DailyClears}  ·  Streak {log.DailyStreak(DailyChallenge.Today.Day)}");
        foreach (var charter in new[] { Charter.Salvager, Charter.Stormchaser })
        {
            var rules = CharterRules.For(charter);
            bool owned = log.Owns(charter);
            col.AddChild(Label(rules.Description, 17));
            col.AddChild(Button(owned ? $"{rules.Name} charter unlocked" : $"Unlock {rules.Name} · {rules.Price} silver",
                () => { if (log.Unlock(charter)) { audio.Play("upgrade"); BuildMenu(); } },
                disabled: owned || log.Silver < rules.Price, purchase: !owned));
        }
        col.AddChild(Label("Fastest hunts", 22, true));
        var times = new GridContainer { Columns = 4 };
        times.AddThemeConstantOverride("h_separation", 15);
        times.AddThemeConstantOverride("v_separation", 6);
        col.AddChild(times);
        times.AddChild(new Control());
        foreach (var charter in Enum.GetValues<Charter>())
        {
            var label = Label(CharterRules.For(charter).Name, 15, false, NauticalPalette.Gold);
            label.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill;
            times.AddChild(label);
        }
        foreach (var boat in Enum.GetValues<BoatKind>())
        {
            times.AddChild(Label(BoatSpec.For(boat).Name, 16));
            foreach (var charter in Enum.GetValues<Charter>())
            {
                float time = (float)log.BestTime(boat, charter);
                times.AddChild(Label(time > 0 ? ClockText(time) : "—", 16, color: time > 0 ? NauticalPalette.Aqua : new Color(NauticalPalette.Cream, .52f)));
            }
        }

        var actions = new HBoxContainer();
        actions.AddThemeConstantOverride("separation", 8);
        col.AddChild(actions);
        var locker = Button("Sail locker", OpenSailLocker);
        locker.SizeFlagsHorizontal = Control.SizeFlags.ExpandFill;
        actions.AddChild(locker);
        AddMuteButton(actions);
        col.AddChild(Button("Back", () => { journal = false; BuildMenu(); }, true));
    }

    void AddMuteButton(Container parent) => parent.AddChild(Button(log.Muted ? "Sound off · turn on" : "Sound on · mute",
        () => { log.ToggleMute(); audio.Muted = log.Muted; BuildMenu(); }));

    static string ClockText(float seconds)
    {
        int time = (int)seconds;
        return $"{time / 60}:{time % 60:00}";
    }

    string VoyageSummary() => $"{Run.Rules.Name}  ·  {ClockText(Run.CombatTime)}  ·  Level {Run.Level}\n" +
        $"{Run.BeaconsLit}/{Run.Beacons.Count} beacons  ·  {Run.Kills} beasts  ·  Longest chain {Run.LongestChain}  ·  +{Run.SilverEarned} silver" +
        (Run.Salvage.Delivered ? "\nWreck salvage delivered" : "") + DailyResult() + SailUnlockResult();

    void UpgradeMenu()
    {
        bool specialty = Run.UpgradeChoices.Any(option => option >= Voyage.FirstSpecialtyOption);
        var col = specialty
            ? Panel(660, "Choose a specialty", "This choice lasts the rest of the voyage.")
            : Panel(660, "Fit an upgrade", $"Level {Run.Level - Run.PendingUpgrades + 1}  ·  {Run.WeaponCount}/{Voyage.WeaponSlots} weapons equipped");
        foreach (int option in Run.UpgradeChoices) AddUpgradeRow(col, option);
        if (Run.UpgradeChoices.Count == 0) col.AddChild(Button("Restore 25 health", () => { Run.TakeUpgradeHeal(); BuildMenu(); }, true));
    }
    void AddUpgradeRow(VBoxContainer column, int option)
    {
        var button = Button("", () => { if (Run.Upgrade(option)) BuildMenu(); });
        var combo = WeaponCombo.ForUpgrade(option);
        button.CustomMinimumSize = new(0, combo == null ? 91 : 114);
        button.TooltipText = Voyage.UpgradeNames[option];
        // Child content stays readable while the entire row handles mouse and keyboard input.
        button.AddThemeStyleboxOverride("hover", Box(new Color("194454"), 9, NauticalPalette.Aqua));
        button.AddThemeStyleboxOverride("pressed", Box(new Color("205463"), 9, NauticalPalette.Aqua));
        column.AddChild(button);
        var row = new HBoxContainer();
        row.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        row.OffsetLeft = row.OffsetTop = 16; row.OffsetRight = row.OffsetBottom = -16;
        row.AddThemeConstantOverride("separation", 18); button.AddChild(row);
        row.AddChild(new UpgradeSymbol { Kind = option, CustomMinimumSize = new(40, 40), SizeFlagsVertical = Control.SizeFlags.ShrinkCenter });
        var text = new VBoxContainer { SizeFlagsHorizontal = Control.SizeFlags.ExpandFill, SizeFlagsVertical = Control.SizeFlags.ShrinkCenter };
        text.AddThemeConstantOverride("separation", 6); row.AddChild(text);
        string rank = Run.Rank(option) == 0 ? "New" : $"Rank {Run.Rank(option)} → {Run.Rank(option) + 1}";
        text.AddChild(Label(option >= Voyage.FirstSpecialtyOption ? Voyage.UpgradeNames[option] : $"{Voyage.UpgradeNames[option]} · {rank}", 23, true));
        text.AddChild(Label(Run.UpgradeBenefit(option), 18));
        if (combo != null)
        {
            int partner = combo.Partner(option);
            bool completesPair = Run.Rank(partner) > 0;
            string pairing = completesPair ? $"{combo.Name} · {combo.Description}"
                : $"Pair with {Voyage.UpgradeNames[partner]} for {combo.Name}";
            text.AddChild(Label(pairing, 14, color: completesPair ? NauticalPalette.Gold : new Color(NauticalPalette.Cream, .68f)));
        }
        ReleaseMenuInput(row);
    }
    void ControlsMenu()
    {
        var col = Panel(680, "Captain’s handbook", "Your crew aims and fires. You steer, dodge and time the boat’s maneuver.");
        col.AddChild(Label("WASD / arrows   Steer\nLeft-click   Plot a course\nRight-click   Cancel the course\nSpace / Shift   Hold to boost\nE   Boat maneuver\nF   Tie up at the repair berth\nTab   Voyage chart\nEsc   Pause\n\nController   Left stick to steer · RB to boost · X for maneuver · A to tie up · Y for chart · Start to pause", 19));
        col.AddChild(Label("Hold Breakwater, keep moving inside Gull Shoal’s ring, and defeat the keeper at Smuggler’s Light. Click Gull Shoal’s marker to plot a patrol. Light all three beacons to summon Crownclaw early, or meet it at 8:00. Bait its charge into rocks to leave its shell open longer.", 18));
        col.AddChild(Label("Defeat beasts and find beach chests to level up. Fit a weapon’s listed partner to unlock their combination. Chain four kills for XP, boost and silver. Floating barrels repair your hull. Return to harbor once per voyage for a larger repair.", 18));
        col.AddChild(Label("Follow the red flag on the compass to salvage a wreck. Sail close to hook the cargo and tow it to any beacon for a refit. Long boosts can snap the line.", 18));
        col.AddChild(Button("Back", () => { controls = false; BuildMenu(); }, true));
    }
}
