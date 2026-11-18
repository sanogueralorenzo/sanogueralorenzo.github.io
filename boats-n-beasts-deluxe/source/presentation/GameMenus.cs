using Godot;
using BoatsNBeasts.Core;
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
    Button Button(string text, Action action, bool primary = false, bool disabled = false)
    {
        var b = new Button { Text = text, CustomMinimumSize = new(0, 46), Disabled = disabled, MouseDefaultCursorShape = Control.CursorShape.PointingHand };
        b.AddThemeFontOverride("font", bodyFont); b.AddThemeFontSizeOverride("font_size", 19);
        b.AddThemeColorOverride("font_color", primary ? NauticalPalette.Navy : NauticalPalette.Cream); b.AddThemeColorOverride("font_hover_color", NauticalPalette.Navy); b.AddThemeColorOverride("font_focus_color", primary ? NauticalPalette.Navy : NauticalPalette.Cream); b.AddThemeColorOverride("font_pressed_color", NauticalPalette.Navy); b.AddThemeColorOverride("font_disabled_color", new Color(NauticalPalette.Cream, .34f));
        b.AddThemeStyleboxOverride("normal", Box(primary ? NauticalPalette.Aqua : new Color("102e43"), 9, primary ? null : new Color("345064")));
        b.AddThemeStyleboxOverride("hover", Box(NauticalPalette.Aqua, 9)); b.AddThemeStyleboxOverride("pressed", Box(NauticalPalette.Aqua, 9)); b.AddThemeStyleboxOverride("focus", Box(new Color(0, 0, 0, 0), 9, NauticalPalette.Aqua)); b.AddThemeStyleboxOverride("disabled", Box(new Color("102838"), 9));
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
                else if (replayingHunt is { } hunt) HuntReplayMenu(hunt);
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
            case VoyageMode.Victory:
                VoyageReport(); break;
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

    void AddMuteButton(Container parent) => parent.AddChild(Button(log.Muted ? "Sound off · turn on" : "Sound on · mute",
        () => { log.ToggleMute(); audio.Muted = log.Muted; BuildMenu(); }));

    static string ClockText(float seconds)
    {
        int time = (int)seconds;
        return $"{time / 60}:{time % 60:00}";
    }

    void UpgradeMenu()
    {
        if (pendingSwap is { } incoming && Run.IsSwapOffer(incoming))
        {
            SwapWeaponMenu(incoming);
            return;
        }
        pendingSwap = null;
        bool specialty = Run.UpgradeChoices.Any(option => option >= Voyage.FirstSpecialtyOption);
        var col = specialty
            ? Panel(660, "Choose a specialty", "This choice lasts the rest of the voyage.")
            : Panel(660, "Fit an upgrade", $"Level {Run.Level - Run.PendingUpgrades + 1}  ·  {Run.WeaponCount}/{Voyage.WeaponSlots} weapons equipped");
        foreach (int option in Run.UpgradeChoices) AddUpgradeRow(col, option);
        if (Run.CanTakeUpgradeHeal)
            col.AddChild(Button("Restore 25 hull", () => { Run.TakeUpgradeHeal(); BuildMenu(); }, true));
    }
    void AddUpgradeRow(VBoxContainer column, int option)
    {
        bool swap = Run.IsSwapOffer(option);
        int rank = Run.Rank(option);
        string change = swap ? "Swap" : rank == 0 ? "New" : $"Rank {rank} → {rank + 1}";
        string title = option >= Voyage.FirstSpecialtyOption ? Voyage.UpgradeNames[option] : $"{Voyage.UpgradeNames[option]} · {change}";
        string detail = swap ? $"Replace a deck weapon. {Voyage.UpgradeNames[option]} inherits its rank." : Run.UpgradeBenefit(option);
        string? note = null;
        Color? noteColor = null;
        var combo = WeaponCombo.ForUpgrade(option);
        if (combo != null)
        {
            int partner = combo.Partner(option);
            bool completesPair = Run.Rank(partner) > 0;
            note = completesPair ? $"{combo.Name} · {combo.Description}" : $"Pair with {Voyage.UpgradeNames[partner]} for {combo.Name}";
            noteColor = completesPair ? NauticalPalette.Gold : new Color(NauticalPalette.Cream, .68f);
        }
        AddRefitRow(column, option, title, detail, () =>
        {
            if (swap) pendingSwap = option;
            else if (!Run.Upgrade(option)) return;
            BuildMenu();
        }, note, noteColor);
    }

    void AddRefitRow(VBoxContainer column, int option, string title, string detail, Action action,
        string? note = null, Color? noteColor = null)
    {
        var button = Button("", action);
        button.CustomMinimumSize = new(0, note == null ? 91 : 114);
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
        text.AddChild(Label(title, 23, true));
        text.AddChild(Label(detail, 18));
        if (note != null) text.AddChild(Label(note, 14, color: noteColor));
        ReleaseMenuInput(row);
    }
    void ControlsMenu()
    {
        var col = Panel(680, "Captain’s handbook", "Your crew aims and fires. You steer, dodge and time the boat’s maneuver.");
        col.AddChild(Label("WASD / arrows   Steer\nLeft-click   Plot a course\nRight-click   Cancel the course\nSpace / Shift   Hold to boost\nE   Boat maneuver\nF   Signal at a beacon or tie up at the repair berth\nTab   Voyage chart\nEsc   Pause\n\nController   Left stick to steer · RB to boost · X for maneuver · A to interact · Y for chart · Start to pause", 19));
        col.AddChild(Label("Hold Breakwater, patrol Gull Shoal, and dodge the keeper’s lunge at Smuggler’s Light to attack while it’s exposed. Signal Crownclaw from a lit beacon after two. Light all three to summon it with weakened armor. It rises at 8:00 anyway. Bait its charge into rocks to leave its shell open longer.", 18));
        col.AddChild(Label("Defeat beasts and find beach chests to level up. Fit a weapon’s partner to unlock their combination. Chain four kills for XP, boost and silver. Escape a blast at the last moment to recover boost and extend an active chain. Tie up at harbor for one repair per voyage.", 18));
        col.AddChild(Label("Follow the red flag on the compass to salvage a wreck. Sail close to hook the cargo and tow it to any beacon for a refit. Long boosts can snap the line.", 18));
        col.AddChild(Button("Back", () => { controls = false; BuildMenu(); }, true));
    }
}
