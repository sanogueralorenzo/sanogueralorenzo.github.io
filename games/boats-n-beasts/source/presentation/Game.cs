using Godot;
using BoatsNBeasts.Core;
using V2 = System.Numerics.Vector2;
namespace BoatsNBeasts;

public partial class Game : Node2D
{
    public Voyage Run = null!;
    OceanView ocean = null!;
    ColorRect water = null!;
    bool mouseHelm, harborStats, toggleBoost, boostLatched;
    Vector2 helmPointer;
    V2? destination;
    readonly List<double> frameSamples = new();
    float performanceClock, lastPerformanceLog;
    double simulationMs;
    int peakEnemyCount, peakShotCount;
    int gameSpeed = 1;
    Hud hud = null!;

    CanvasLayer layer = null!;
    Control menuRoot = null!;
    Font titleFont = null!, bodyFont = null!;
    bool title = true, settings, controls, reducedMotion, fullscreen, assistedFishing;
    BoatKind selectedBoat;
    VoyageMode shownMode = (VoyageMode)(-1), beforePause;
    LineEdit? seedInput;
    uint selectedSeed = 73919;
    int bestKills, completed, silver, creditedSilver;
    bool recorded;
    float elapsed, toastTime;
    string toast = "";


    public override void _Ready()
    {
        bodyFont = ThemeDB.FallbackFont; titleFont = new FontVariation { BaseFont = ThemeDB.FallbackFont, VariationEmbolden = 1.0f };
        Run = new(selectedSeed, BoatKind.Cutter);
        var waterMaterial = new ShaderMaterial { Shader = GD.Load<Shader>("res://source/presentation/ocean.gdshader") };
        water = new ColorRect { Size = GetViewportRect().Size, Material = waterMaterial, MouseFilter = Control.MouseFilterEnum.Ignore }; AddChild(water);
        ocean = new() { Voyage = Run, Menu = true, Water = waterMaterial }; AddChild(ocean);
        LoadSettings();
        layer = new(); AddChild(layer); hud = new() { Game = this, TitleFont = titleFont, BodyFont = bodyFont }; layer.AddChild(hud);
        DisplayServer.WindowSetTitle("Boats n Beasts");
        BuildMenu();
        GD.Print("Boats n Beasts | renderer=", RenderingServer.GetCurrentRenderingMethod(), " | seed=", selectedSeed);
    }
    public override void _Process(double delta)
    {
        water.Size = GetViewportRect().Size;
        if (!title && Run.Mode == VoyageMode.Sailing) { frameSamples.Add(delta * 1000); if(frameSamples.Count>7200)frameSamples.RemoveRange(0,3600); performanceClock += (float)delta; peakEnemyCount = Math.Max(peakEnemyCount, Run.Enemies.Count); peakShotCount = Math.Max(peakShotCount, Run.Shots.Count); }
        if (performanceClock-lastPerformanceLog>30) { lastPerformanceLog=performanceClock; var sorted=frameSamples.Order().ToArray(); GD.Print($"LIVE sailingSeconds={performanceClock:0} frameMeanMs={sorted.Average():0.00} p95Ms={sorted[(int)(sorted.Length*.95)]:0.00} chunks={Run.World.Loaded.Count} enemies={Run.Enemies.Count} shots={Run.Shots.Count} distance={Run.Distance:0} hp={Run.Health:0}"); }
        float dt = (float)Math.Min(delta, .05); elapsed += dt; toastTime = Math.Max(0, toastTime - dt);
        // Repeat bounded simulation steps so faster time preserves collision and combat cadence.
        for (int step = 0; step < (title ? 1 : gameSpeed); step++)
        {
            if (!title && !settings && !controls)
            {
                V2 move = new((Down(Key.D) || Down(Key.Right) ? 1 : 0) - (Down(Key.A) || Down(Key.Left) ? 1 : 0), (Down(Key.S) || Down(Key.Down) ? 1 : 0) - (Down(Key.W) || Down(Key.Up) ? 1 : 0));
                if (move != V2.Zero) { mouseHelm = false; destination = null; }
                if (destination is V2 goal) { var d = goal - Run.Position; if (d.Length() < 45) destination = null; else move = d; }
                if (mouseHelm) { var aim = helmPointer - ocean.Screen(Run.Position); move = aim.Length() > 28 ? new V2(aim.X, aim.Y) : V2.Zero; }
                var tickStart = System.Diagnostics.Stopwatch.GetTimestamp();
                Run.Tick(dt, new(move, (toggleBoost ? boostLatched : Down(Key.Space) || Down(Key.Shift))));
                if (Run.Mode == VoyageMode.Sailing) simulationMs = simulationMs * .95 + System.Diagnostics.Stopwatch.GetElapsedTime(tickStart).TotalMilliseconds * .05;
            }
            ocean.Destination = destination;
            foreach (var e in Run.Events)
            {
                ocean.Effect(e);
                if (e.Kind == "silver") Toast("+1 silver");
                if (e.Kind == "bulwark") Toast("BULWARK · shots cleared, nearby beasts soaked");
                if (e.Kind == "boss") Toast("THE CROWNCLAW RISES  •  Keep moving. Watch the coral warning rings.");
                if (e.Kind == "bossSlain") Toast("THE SEA IS YOURS  •  Return to a harbor to finish your voyage.");
            }
            Run.Events.Clear(); ocean.Advance(dt);
        }
        if (!title && Run.SilverEarned > creditedSilver)
        {
            int earnedSilver = Run.SilverEarned;
            silver += earnedSilver - creditedSilver; creditedSilver = earnedSilver; SaveSettings();
        }
        hud.QueueRedraw();
        if (!title && !settings && !controls && shownMode != Run.Mode) BuildMenu();
    }

    public override void _Input(InputEvent input)
    {
        // Space belongs to sailing/fishing. An upgrade appearing during a boost must
        // not silently choose the focused card, nor instantly retry after defeat.
        if (!title && input is InputEventKey key && key.PhysicalKeycode == Key.Space && Run.Mode is not (VoyageMode.Sailing or VoyageMode.Fishing)) GetViewport().SetInputAsHandled();
    }
    public override void _UnhandledInput(InputEvent input)
    {
        if (input is InputEventMouseButton { Pressed: true, ButtonIndex: MouseButton.Left } click && !title && Run.Mode == VoyageMode.Sailing)
        { var offset = click.Position - ocean.Screen(Run.Position); destination = Run.Position + new V2(offset.X, offset.Y); mouseHelm = false; GetViewport().SetInputAsHandled(); }
        if (input is InputEventMouseMotion motion) helmPointer = motion.Position;
        if (input is InputEventMouseButton { Pressed: true, ButtonIndex: MouseButton.Right } mouse && !title && Run.Mode == VoyageMode.Sailing)
        { destination = null; helmPointer = mouse.Position; mouseHelm = !mouseHelm; Toast(mouseHelm ? "Mouse helm on · point to steer · right-click to stop" : "Mouse helm off"); GetViewport().SetInputAsHandled(); }
    }
    void CaptureReview()
    {
        string folder = ProjectSettings.GlobalizePath("res://evidence"); System.IO.Directory.CreateDirectory(folder);
        string name = DateTime.Now.ToString("yyyyMMdd-HHmmss") + "-" + (title ? "title" : Run.Mode.ToString().ToLowerInvariant());
        GetViewport().GetTexture().GetImage().SavePng(folder + "/" + name + ".png");
        var samples = frameSamples.Order().ToArray();
        string report = $"Mouse viewport={GetViewport().GetMousePosition()} global={GetGlobalMousePosition()} boatScreen={ocean.Screen(Run.Position)} viewportRect={GetViewportRect()}\nNative runtime capture: {name}\nRenderer: {RenderingServer.GetCurrentRenderingMethod()}\nSeed: {Run.World.Seed}\nMode: {Run.Mode}\nGame speed: x{gameSpeed}\nSilver: {silver}; earned this voyage: {Run.SilverEarned}; next eligible combat time: {Run.NextSilverTime:R}\nBoat: {Run.Boat}\nPosition: {Run.Position}\nHealth: {Run.Health}/{Run.MaxHealth}\nCoins: {Run.Coins}; cargo: {Run.Hold.Count}; charts: {Run.Charts}; kills: {Run.Kills}; level: {Run.Level}\nActive chunks: {Run.World.Loaded.Count}; enemies: {Run.Enemies.Count}; shots: {Run.Shots.Count}\nActual sailing seconds: {performanceClock:0.0}; peak enemies: {peakEnemyCount}; peak shots: {peakShotCount}\n";
        report += $"Combat clock={Run.CombatTime:R}; director={Run.Director.Clock:R}/{Run.Director.Credits:R}; boost={Run.Boost:R}; invulnerable={Run.Invulnerable:R}; ability={Run.AbilityCharge:R}/{Run.Slipstream:R}\nWeapon ranks={string.Join(",",Run.Weapons)}; cooldowns={string.Join(",",Run.Cooldowns.Select(x=>x.ToString("R")))}\nDepletion={string.Join(";",Run.World.Depletion.Select(x=>$"{x.Key}={x.Value}"))}\n";
        foreach (var enemy in Run.Enemies) report += $"Enemy {enemy.Id}: {enemy.Kind} position={enemy.Position} hp={enemy.Health:R} time={enemy.Time:R} attack={enemy.AttackClock:R} tell={enemy.Telegraph:R} dash={enemy.Dash:R} mark={enemy.Mark:R}\n";
        foreach (var shot in Run.Shots) report += $"Shot {shot.Kind} hostile={shot.Hostile} position={shot.Position} life={shot.Life:R}\n";
        report += $"CPU simulation average ms={simulationMs:0.000}; draw submission average ms={ocean.DrawMs:0.000}; cached scenery={ocean.CachedScenery}; engine FPS={Engine.GetFramesPerSecond()}; draw calls={Performance.GetMonitor(Performance.Monitor.RenderTotalDrawCallsInFrame)}; objects={Performance.GetMonitor(Performance.Monitor.RenderTotalObjectsInFrame)}\n";
        if (samples.Length > 0) report += $"Frame ms mean: {samples.Average():0.00}; p95: {samples[(int)(samples.Length*.95)]:0.00}; p99: {samples[(int)(samples.Length*.99)]:0.00}\n";
        System.IO.File.WriteAllText(folder + "/" + name + ".txt", report); GD.Print(report);
    }
    static bool Down(Key key) => Input.IsPhysicalKeyPressed(key);
    public override void _UnhandledKeyInput(InputEvent @event)
    {
        if (@event is not InputEventKey key || !key.Pressed || key.Echo) return;
        if (key.Keycode == Key.F12) { CaptureReview(); return; }
        if (key.Keycode == Key.F11) { fullscreen = !fullscreen; ApplySettings(); SaveSettings(); return; }
        if (key.Keycode == Key.Escape)
        {
            if (settings || controls) { settings = controls = false; BuildMenu(); }
            else if (!title)
            {
                if (Run.Mode == VoyageMode.Fishing) Run.CancelFishing();
                else if (Run.Mode is VoyageMode.Catch or VoyageMode.Harbor) Run.Mode = VoyageMode.Sailing;
                else if (Run.Mode == VoyageMode.Paused) Run.Mode = beforePause;
                else if (Run.Mode == VoyageMode.Sailing) { destination = null; mouseHelm = boostLatched = false; beforePause = Run.Mode; Run.Mode = VoyageMode.Paused; }
                BuildMenu();
            }
            GetViewport().SetInputAsHandled(); return;
        }
        if (title || settings || controls) return;
        if (toggleBoost && Run.Mode == VoyageMode.Sailing && key.PhysicalKeycode is Key.Space or Key.Shift) { boostLatched = !boostLatched; return; }
        if (Run.Mode == VoyageMode.Fishing && (key.PhysicalKeycode == Key.Space || key.PhysicalKeycode == Key.E)) { Run.Reel(); GetViewport().SetInputAsHandled(); }
        else if (Run.Mode == VoyageMode.Sailing && key.PhysicalKeycode == Key.E)
        {
            destination = null; mouseHelm = boostLatched = false;
            if (!Run.Interact()) Toast(Run.Hold.Count >= 12 ? "Your hold is full. Sell your catch at a harbor." : "Sail close to a fishing school or harbor, then press E.");
            BuildMenu();
        }
        else if (Run.Mode == VoyageMode.Catch && key.Keycode == Key.Enter) { Run.Mode = VoyageMode.Sailing; BuildMenu(); }
    }
    public override void _Notification(int what)
    {
        if (what == NotificationApplicationFocusOut && Run != null && !title && Run.Mode is VoyageMode.Sailing or VoyageMode.Fishing)
        { beforePause = Run.Mode; destination = null; mouseHelm = boostLatched = false; Run.Mode = VoyageMode.Paused; Callable.From(BuildMenu).CallDeferred(); }
    }
    void Start()
    {
        if (seedInput != null && GodotObject.IsInstanceValid(seedInput) && uint.TryParse(seedInput.Text, out uint seed)) selectedSeed = seed;
        creditedSilver = 0; gameSpeed = 1; mouseHelm = boostLatched = false; destination = null; frameSamples.Clear(); performanceClock = lastPerformanceLog = 0; peakEnemyCount = peakShotCount = 0;
        seedInput = null;
        Run = new(selectedSeed, selectedBoat) { AssistedFishing = assistedFishing }; title = settings = controls = recorded = false;
        ocean.Voyage = Run; ocean.Menu = false; ocean.Reset();
        Toast("WASD or click to sail  •  Space to boost  •  E to fish / dock"); BuildMenu();
    }
    void BackToTitle()
    {
        Record(); title = true; settings = controls = false; ocean.Menu = true;
        Run = new(selectedSeed, selectedBoat); ocean.Voyage = Run; ocean.Reset(); BuildMenu();
    }
    void Record()
    {
        if (title) return; bestKills = Math.Max(bestKills, Run.Kills); if (Run.Retired && !recorded) { completed++; recorded = true; } SaveSettings();
    }
    void Toast(string text) { toast = text; toastTime = 5; }
    StyleBoxFlat Box(Color bg, int radius = 14, Color? border = null)
    {
        var s = new StyleBoxFlat { BgColor = bg, CornerRadiusTopLeft = radius, CornerRadiusTopRight = radius, CornerRadiusBottomLeft = radius, CornerRadiusBottomRight = radius, ContentMarginLeft = 22, ContentMarginRight = 22, ContentMarginTop = 15, ContentMarginBottom = 15 };
        if (border != null) { s.BorderColor = border.Value; s.SetBorderWidthAll(2); } return s;
    }
    Label Label(string text, int size = 22, bool heading = false, Color? color = null)
    {
        var l = new Label { Text = text, AutowrapMode = TextServer.AutowrapMode.WordSmart };
        l.AddThemeFontOverride("font", heading ? titleFont : bodyFont); l.AddThemeFontSizeOverride("font_size", size); l.AddThemeColorOverride("font_color", color ?? OceanView.Cream); return l;
    }
    Button Button(string text, Action action, bool primary = false, bool disabled = false)
    {
        var b = new Button { Text = text, CustomMinimumSize = new(0, 52), Disabled = disabled, MouseDefaultCursorShape = Control.CursorShape.PointingHand };
        b.AddThemeFontOverride("font", bodyFont); b.AddThemeFontSizeOverride("font_size", 21);
        b.AddThemeColorOverride("font_color", primary ? OceanView.Navy : OceanView.Cream); b.AddThemeColorOverride("font_hover_color", OceanView.Navy); b.AddThemeColorOverride("font_focus_color", primary ? OceanView.Navy : OceanView.Cream); b.AddThemeColorOverride("font_pressed_color", OceanView.Navy); b.AddThemeColorOverride("font_disabled_color", new Color(OceanView.Cream, .34f));
        b.AddThemeStyleboxOverride("normal", Box(primary ? OceanView.Cream : new Color("103970"), 9, primary ? null : new Color("386294")));
        b.AddThemeStyleboxOverride("hover", Box(new Color("f8cf85"), 9)); b.AddThemeStyleboxOverride("pressed", Box(OceanView.Aqua, 9)); b.AddThemeStyleboxOverride("focus", Box(new Color(0, 0, 0, 0), 9, OceanView.Aqua)); b.AddThemeStyleboxOverride("disabled", Box(new Color("123361"), 9));
        b.Pressed += () => { action(); }; return b;
    }
    VBoxContainer Panel(float width, string eyebrow, string heading, string detail)
    {
        var center = new CenterContainer(); center.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect); menuRoot.AddChild(center);
        var panel = new PanelContainer { CustomMinimumSize = new(width, 0) }; panel.AddThemeStyleboxOverride("panel", Box(new Color("082953"), 18, new Color("507195"))); center.AddChild(panel);
        var column = new VBoxContainer(); column.AddThemeConstantOverride("separation", 14); panel.AddChild(column);
        column.AddChild(Label(eyebrow, 17, false, OceanView.Aqua)); column.AddChild(Label(heading, 48, true)); column.AddChild(Label(detail, 20));
        return column;
    }
    void BuildMenu()
    {
        if (menuRoot != null) { layer.RemoveChild(menuRoot); menuRoot.QueueFree(); }
        menuRoot = new Control { MouseFilter = Control.MouseFilterEnum.Ignore }; menuRoot.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect); layer.AddChild(menuRoot);
        shownMode = Run.Mode;
        if (settings) { SettingsMenu(); FocusFirst(menuRoot); return; }
        if (controls) { ControlsMenu(); FocusFirst(menuRoot); return; }
        if (title) { TitleMenu(); FocusFirst(menuRoot); return; }
        if (Run.Mode == VoyageMode.Sailing || Run.Mode == VoyageMode.Fishing)
        {
            var speed = new Button
            {
                Text = $"×{gameSpeed}", TooltipText = "Game speed · click to cycle ×1 / ×2 / ×3",
                FocusMode = Control.FocusModeEnum.None,
                MouseDefaultCursorShape = Control.CursorShape.PointingHand,
                OffsetLeft = 14, OffsetRight = 88,
                OffsetTop = 68, OffsetBottom = 106
            };
            speed.AddThemeFontOverride("font", bodyFont); speed.AddThemeFontSizeOverride("font_size", 20);
            speed.AddThemeColorOverride("font_color", new Color(OceanView.Cream, .75f));
            speed.AddThemeStyleboxOverride("normal", Box(new Color(OceanView.Navy, .5f), 8));
            speed.AddThemeStyleboxOverride("hover", Box(new Color("19477a"), 8));
            speed.AddThemeStyleboxOverride("pressed", Box(new Color("245b87"), 8));
            foreach (string state in new[] { "normal", "hover", "pressed" })
            {
                var style = (StyleBoxFlat)speed.GetThemeStylebox(state);
                style.ContentMarginTop = style.ContentMarginBottom = 4;
                style.ContentMarginLeft = style.ContentMarginRight = 10;
            }
            speed.Pressed += () => { gameSpeed = gameSpeed % 3 + 1; speed.Text = $"×{gameSpeed}"; };
            menuRoot.AddChild(speed);
            return;
        }
        var shade = new ColorRect { Color = new(0.015f, .06f, .16f, .66f), MouseFilter = Control.MouseFilterEnum.Stop }; shade.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect); menuRoot.AddChild(shade);
        VBoxContainer col;
        switch (Run.Mode)
        {
            case VoyageMode.Paused:
                col = Panel(510, "TAKE A BREATHER", "At anchor", Run.Retired ? "Voyage won · explore the endless ocean" : Run.BossSlain ? "Return to a harbor to claim your victory." : Run.Charts >= 3 ? "Sail beyond 3 leagues and defeat the Crownclaw." : $"Chart {Run.Charts}/3 · Fish at three different schools beyond one league.");
                col.AddChild(Button("Resume voyage", () => { Run.Mode = beforePause; BuildMenu(); }, true));
                col.AddChild(Button("Settings", () => { settings = true; BuildMenu(); }));
                col.AddChild(Button("Captain’s handbook", () => { controls = true; BuildMenu(); }));
                col.AddChild(Button("End voyage · return to title", BackToTitle)); break;
            case VoyageMode.Harbor: HarborMenu(); break;
            case VoyageMode.Upgrade: UpgradeMenu(); break;
            case VoyageMode.Catch:
                col = Panel(610, "CATCH OF THE DAY", Run.CatchTitle, Run.CatchDetail);
                col.AddChild(Label($"Cargo {Run.Hold.Count}/12   •   Chart fragments {Run.Charts}/3", 21, false, OceanView.Aqua));
                col.AddChild(Button("Back to the blue  [Enter]", () => { Run.Mode = VoyageMode.Sailing; BuildMenu(); }, true)); break;
            case VoyageMode.Defeat:
                Record(); col = Panel(570, "EVERY CAPTAIN HAS A STORY", "Lost to the deep", $"{Run.Kills} beasts defeated  •  {Run.MaxDistance / 1000:0.0} leagues offshore\n{Run.Charts}/3 chart fragments  •  Level {Run.Level}");
                col.AddChild(Label("Fish, sell, and refit before pushing farther offshore. Boost softens incoming damage.", 20));
                col.AddChild(Button("Sail again · same ocean", Start, true)); col.AddChild(Button("Choose another boat", BackToTitle)); break;
            case VoyageMode.Victory:
                Record(); col = Panel(610, "A LEGEND COMES HOME", "The sea is yours", $"The Crownclaw is defeated. Your charts brought you home.\n{Run.Kills} beasts  •  {Run.Distance / 1000:0.0} leagues sailed  •  {Run.Coins} gold");
                col.AddChild(Button("Keep exploring the endless ocean", () => { Run.Mode = VoyageMode.Sailing; BuildMenu(); }, true)); col.AddChild(Button("A new voyage", BackToTitle)); break;
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
        seedInput = null;
        var shade = new ColorRect { Color = new(.025f, .105f, .25f, .94f), Position = Vector2.Zero, Size = new(600, 1000), MouseFilter = Control.MouseFilterEnum.Ignore }; menuRoot.AddChild(shade);
        var col = new VBoxContainer { Position = new(58, 42), Size = new(472, 810) }; col.AddThemeConstantOverride("separation", 13); menuRoot.AddChild(col);
        col.AddChild(Label("AN ENDLESS OCEAN. ONE LITTLE BOAT.", 17, false, OceanView.Aqua));
        col.AddChild(Label("BOATS n\nBEASTS", 60, true));
        col.AddChild(Label("Sail into trouble. Fish for fortune.\nCome home a legend.", 24));
        var choices = new HBoxContainer(); choices.AddThemeConstantOverride("separation", 10); col.AddChild(choices);
        choices.AddChild(Button(selectedBoat == BoatKind.Cutter ? "✓  CUTTER" : "CUTTER", () => { ReadSeed(); selectedBoat = BoatKind.Cutter; Run.Boat = selectedBoat; BuildMenu(); }, selectedBoat == BoatKind.Cutter));
        choices.AddChild(Button(selectedBoat == BoatKind.Trawler ? "✓  TRAWLER" : "TRAWLER", () => { ReadSeed(); selectedBoat = BoatKind.Trawler; Run.Boat = selectedBoat; BuildMenu(); }, selectedBoat == BoatKind.Trawler));
        var spec = BoatSpec.For(selectedBoat);
        col.AddChild(Label($"{spec.Ability}  •  {spec.Hull} hull\n{spec.Description}", 20, false, OceanView.Cream));
        var row = new HBoxContainer(); col.AddChild(row); var seedLabel = Label("OCEAN SEED", 18); seedLabel.CustomMinimumSize = new(120, 42); seedLabel.AutowrapMode = TextServer.AutowrapMode.Off; row.AddChild(seedLabel);
        seedInput = new LineEdit { Text = selectedSeed.ToString(), MaxLength = 10, CustomMinimumSize = new(185, 42), SizeFlagsHorizontal = Control.SizeFlags.ExpandFill };
        seedInput.AddThemeFontOverride("font", bodyFont); seedInput.AddThemeFontSizeOverride("font_size", 20); row.AddChild(seedInput);
        row.AddChild(Button("↻", () => { selectedSeed = (uint)Random.Shared.Next(1, int.MaxValue); seedInput.Text = selectedSeed.ToString(); }));
        var sailButton = Button("SET SAIL", Start, true); col.AddChild(sailButton);
        seedInput.TooltipText = "Whole number from 0 to 4294967295";
        seedInput.TextChanged += value => sailButton.Disabled = !uint.TryParse(value, out _);
        var bottom = new HBoxContainer(); bottom.AddThemeConstantOverride("separation", 10); col.AddChild(bottom);
        bottom.AddChild(Button("Handbook", () => { ReadSeed(); controls = true; BuildMenu(); })); bottom.AddChild(Button("Settings", () => { ReadSeed(); settings = true; BuildMenu(); })); bottom.AddChild(Button("Quit", () => GetTree().Quit()));
        col.AddChild(Label($"SILVER {silver}  •  Saved between voyages\nBEST {bestKills} BEASTS   •   {completed} VOYAGES WON", 16, false, new Color(OceanView.Cream, .55f)));
    }
    void ReadSeed() { if (seedInput != null && uint.TryParse(seedInput.Text, out uint value)) selectedSeed = value; seedInput = null; }
    void HarborMenu()
    {
        var col = Panel(950, "LIGHTHOUSE HARBOR  /  SAFE WATERS", "A little shore leave", $"{Run.Coins} gold   •   Hull {Run.Health:0}/{Run.MaxHealth:0}   •   Cargo {Run.Hold.Count}/12");
        col.AddThemeConstantOverride("separation", 7);
        var row = new HBoxContainer(); row.AddThemeConstantOverride("separation", 10); col.AddChild(row);
        row.AddChild(Button($"Sell catch · +{Run.Hold.Sum(f => f.Value)}", () => { Run.Sell(); BuildMenu(); }, true, Run.Hold.Count == 0));
        row.AddChild(Button($"Repair · {Run.RepairCost} gold", () => { Run.Repair(); BuildMenu(); }, false, Run.RepairCost == 0 || Run.Coins < Run.RepairCost));
        if (Run.BossSlain && !Run.Retired) row.AddChild(Button("Claim victory", () => { Run.ClaimVictory(); BuildMenu(); }, true));
        else row.AddChild(Button($"Switch to {(Run.Boat == BoatKind.Cutter ? "Trawler" : "Cutter")}", () => { Run.SwitchBoat(); BuildMenu(); }));
        col.AddChild(Label($"{Run.Spec.Ability} · {Run.Spec.Description}", 17, false, OceanView.Aqua));
        col.AddChild(Button(harborStats ? "SHOW WEAPONS  /  Ship upgrades selected" : "SHOW SHIP UPGRADES  /  Weapons selected", () => { harborStats = !harborStats; BuildMenu(); }));
        var grid = new GridContainer { Columns = 2 }; grid.AddThemeConstantOverride("h_separation", 14); grid.AddThemeConstantOverride("v_separation", 8); col.AddChild(grid);
        for (int i = harborStats ? 6 : 0; i < (harborStats ? Voyage.UpgradeNames.Length : 6); i++)
        {
            int option = i; var box = new VBoxContainer { CustomMinimumSize = new(438, 0) }; grid.AddChild(box);
            box.AddChild(Label(Voyage.UpgradeNames[i] + $"  {Run.Rank(i)}/5", 23, true)); box.AddChild(Label(Voyage.UpgradeDescriptions[i], 16));
            box.AddChild(Button(Run.Rank(i) >= 5 ? "Fully upgraded" : $"{(Run.Rank(i) == 0 ? "Install" : "Upgrade")} · {Run.UpgradeCost(i)} gold", () => { Run.Upgrade(option); BuildMenu(); }, false, Run.Rank(i) >= 5 || Run.Coins < Run.UpgradeCost(i)));
        }
        col.AddChild(Button("Back to open water  [Esc]", () => { Run.Mode = VoyageMode.Sailing; BuildMenu(); }, !Run.BossSlain || Run.Retired));
    }
    void UpgradeMenu()
    {
        var col = Panel(1000, $"CAPTAIN LEVEL {Run.Level}", "Make it your boat", "Choose one free upgrade. All boats can use every weapon. Your voyage waits.");
        var row = new HBoxContainer(); row.AddThemeConstantOverride("separation", 18); col.AddChild(row);
        foreach (int option in Run.UpgradeChoices)
        {
            var box = new VBoxContainer { CustomMinimumSize = new(304, 0), SizeFlagsHorizontal = Control.SizeFlags.ExpandFill }; box.AddThemeConstantOverride("separation", 14); row.AddChild(box);
            box.AddChild(Label(Run.Rank(option) == 0 ? "NEW EQUIPMENT" : $"RANK {Run.Rank(option)} → {Run.Rank(option) + 1}", 17, false, OceanView.Aqua));
            box.AddChild(Label(Voyage.UpgradeNames[option], 29, true));
            var detail = Label(Voyage.UpgradeDescriptions[option], 20); detail.CustomMinimumSize = new(0, 140); box.AddChild(detail);
            box.AddChild(Button("Choose", () => { Run.Upgrade(option, true); BuildMenu(); }, option == Run.UpgradeChoices[0]));
        }
        if (Run.UpgradeChoices.Count == 0) col.AddChild(Button("All fitted · take 40 gold", () => { Run.Coins += 40; Run.Mode = VoyageMode.Sailing; BuildMenu(); }, true));
    }
    void ControlsMenu()
    {
        var col = Panel(900, "CAPTAIN’S HANDBOOK", "A life on the water", "Your guns aim and fire automatically. You captain the boat.");
        col.AddThemeConstantOverride("separation", 8);
        col.AddChild(Label("WASD / arrows     Sail in any direction\nLeft-click                 Sail to a point and stop\nRight-click              Toggle continuous mouse helm\nSpace / Shift          Boost; reduces damage while moving\nE                               Fish at ripples, or dock at a harbor\nSpace / E                 Reel when the marker is in the turquoise band\nEsc                            Pause, leave harbor, or cancel fishing\nF11                            Toggle fullscreen", 19));
        col.AddChild(Label("THE VOYAGE", 25, true, OceanView.Aqua));
        col.AddChild(Label("Catch fish at 3 different schools beyond 1 league to complete your chart. Sail beyond 3 leagues, defeat the Crownclaw, then dock at any harbor to win. You can keep exploring afterward.\n\nSell fish, repair, and refit at harbors. All boats support ranged, aura and close attacks. Cutter boost speeds up weapons; Trawler slow sailing charges its defensive pulse. Swaps preserve upgrades and hull percentage.\n\nFishing freezes combat, including the result screen. Land 3 reels before 3 misses or 16 seconds. Each completed cast depletes one fish. Settings includes assisted fishing and toggle boost. New voyages reset catches and upgrades.", 19));
        col.AddChild(Button("Understood", () => { controls = false; BuildMenu(); }, true));
    }
    void SettingsMenu()
    {
        var col = Panel(590, "MAKE YOURSELF COMFORTABLE", "Settings", "Changes are saved automatically.");
        col.AddChild(Button(fullscreen ? "Fullscreen · on" : "Fullscreen · off", () => { fullscreen = !fullscreen; ApplySettings(); SaveSettings(); BuildMenu(); }));
        col.AddChild(Button(reducedMotion ? "Reduced motion · on" : "Reduced motion · off", () => { reducedMotion = !reducedMotion; ApplySettings(); SaveSettings(); BuildMenu(); }));
        col.AddChild(Button(toggleBoost ? "Boost control · tap to toggle" : "Boost control · hold", () => { toggleBoost = !toggleBoost; boostLatched = false; SaveSettings(); BuildMenu(); }));
        col.AddChild(Button(assistedFishing ? "Assisted fishing · on" : "Assisted fishing · off", () => { assistedFishing = !assistedFishing; Run.AssistedFishing = assistedFishing; SaveSettings(); BuildMenu(); }));
        col.AddChild(Label("Assisted fishing times your reels automatically. Catches and rewards stay the same.", 18));
        col.AddChild(Button("Back", () => { settings = false; BuildMenu(); }, true));
    }
    void ApplySettings() { ocean.ReducedMotion = reducedMotion; DisplayServer.WindowSetMode(fullscreen ? DisplayServer.WindowMode.Fullscreen : DisplayServer.WindowMode.Windowed); }
    void LoadSettings()
    {
        var cfg = new ConfigFile(); if (cfg.Load("user://settings.cfg") != Error.Ok) return;
        reducedMotion = (bool)cfg.GetValue("display", "reduced_motion", false); fullscreen = (bool)cfg.GetValue("display", "fullscreen", false);
        toggleBoost = (bool)cfg.GetValue("accessibility", "toggle_boost", false);
        assistedFishing = (bool)cfg.GetValue("accessibility", "assisted_fishing", false);
        silver = Math.Max(0, (int)cfg.GetValue("progress", "silver", 0));
        bestKills = (int)cfg.GetValue("progress", "best_kills", 0); completed = (int)cfg.GetValue("progress", "wins", 0); ApplySettings();
    }
    void SaveSettings()
    {
        var cfg = new ConfigFile(); cfg.SetValue("display", "fullscreen", fullscreen); cfg.SetValue("display", "reduced_motion", reducedMotion); cfg.SetValue("accessibility", "toggle_boost", toggleBoost); cfg.SetValue("accessibility", "assisted_fishing", assistedFishing); cfg.SetValue("progress", "best_kills", bestKills); cfg.SetValue("progress", "wins", completed); cfg.SetValue("progress", "silver", silver); cfg.Save("user://settings.cfg");
    }
    public partial class Hud : Node2D
    {
        public Game Game = null!; public Font TitleFont = null!, BodyFont = null!;
        void Text(Vector2 p, string text, int size = 22, bool heading = false, Color? color = null) => DrawString(heading ? TitleFont : BodyFont, p, text, HorizontalAlignment.Left, -1, size, color ?? OceanView.Cream);
        void Bar(Vector2 p, Vector2 size, float value, Color color)
        { DrawStyleBox(Game.Box(new Color(OceanView.Navy, .8f), 5), new(p, size)); DrawStyleBox(Game.Box(color, 5), new(p, new Vector2(size.X * Math.Clamp(value, 0, 1), size.Y))); }
        public override void _Draw()
        {
            if (Game.title) return; var r = Game.Run; var size = GetViewportRect().Size;
            string level = $"LVL {r.Level}";
            Text(new(size.X - 100 - TitleFont.GetStringSize(level, fontSize: 20).X / 2, 38), level, 20, true);
            int seconds = (int)r.CombatTime;
            string[] counters = [$"{seconds / 60:00}:{seconds % 60:00}", Game.silver.ToString(), r.Coins.ToString(), r.Kills.ToString()];
            float countersWidth = counters.Sum(value => BodyFont.GetStringSize(value, fontSize: 21).X + 48) + 12;
            DrawStyleBox(Game.Box(new Color(OceanView.Navy, .55f), 8), new Rect2(14, 16, countersWidth, 44));
            float counterX = 38;
            for (int i = 0; i < counters.Length; i++)
            {
                CounterIcon(new(counterX, 38), i);
                Text(new(counterX + 20, 45), counters[i], 21);
                counterX += BodyFont.GetStringSize(counters[i], fontSize: 21).X + 48;
            }
            var healthPosition = Game.ocean.Screen(r.Position) + new Vector2(-48, -100);
            Bar(healthPosition, new(96, 8), r.Health / r.MaxHealth, new Color("ed4b55"));
            string[] itemLabels = ["CANNON", "HARPOON", "MORTAR", "COIL", "AURA", "SCATTER", "HULL", "ENGINE", "RELOAD", "AREA"];
            var equipped = Enumerable.Range(0, itemLabels.Length).Where(i => r.Rank(i) > 0).ToArray();
            const float itemWidth = 96, gap = 8;
            float rowWidth = equipped.Length * (itemWidth + gap) - gap;
            for (int slot = 0; slot < equipped.Length; slot++)
            {
                int item = equipped[slot];
                var p = new Vector2((size.X - rowWidth) / 2 + slot * (itemWidth + gap), size.Y - 48);
                DrawStyleBox(Game.Box(new Color(OceanView.Navy, .65f), 6), new(p, new Vector2(itemWidth, 32)));
                string label = $"{itemLabels[item]} {r.Rank(item)}";
                float labelWidth = TitleFont.GetStringSize(label, fontSize: 15).X;
                Text(p + new Vector2((itemWidth - labelWidth) / 2, 22), label, 15, true);
            }
            Bar(Vector2.Zero, new(size.X, 8), r.Xp / (float)r.NextXp, OceanView.Aqua);
            DrawCompass(size);
            if (Game.toastTime > 0) { float width = BodyFont.GetStringSize(Game.toast, fontSize: 20).X; DrawStyleBox(Game.Box(new Color(OceanView.Navy, .9f), 10), new((size.X - width) / 2 - 20, 144, width + 40, 45)); Text(new((size.X - width) / 2, 174), Game.toast, 20); }
            if (r.Mode == VoyageMode.Sailing)
            {
                string prompt = r.Safe ? "E  ·  DOCK & REFIT" : r.World.FishAt(r.Position) != null ? "E  ·  CAST A LINE" : "";
                if (prompt != "") { var p = new Vector2(size.X / 2 - 120, size.Y / 2 + 110); DrawStyleBox(Game.Box(OceanView.Cream, 10), new(p, new Vector2(240, 46))); Text(p + new Vector2(17, 30), prompt, 23, true, OceanView.Navy); }
            }
            if (r.Mode == VoyageMode.Fishing)
            {
                var p = new Vector2(size.X / 2 - 285, size.Y - 270); DrawStyleBox(Game.Box(new Color("082953"), 16, OceanView.Cream), new(p, new Vector2(570, 164)));
                Text(p + new Vector2(25, 37), "A QUIET MOMENT", 29, true); Text(p + new Vector2(347, 34), $"{r.FishHits}/3 REELS   {r.FishMisses}/3 MISSES", 17);
                Text(p + new Vector2(25, 64), r.AssistedFishing ? "Combat frozen · assisted reel is on · enjoy the quiet" : "Combat frozen · Space / E when the marker enters turquoise", 18);
                var bar = p + new Vector2(25, 87); DrawStyleBox(Game.Box(OceanView.Navy, 7), new(bar, new Vector2(520, 28)));
                DrawStyleBox(Game.Box(OceanView.Aqua, 6), new(bar + new Vector2((r.FishTarget - r.FishBand) * 520, 0), new Vector2(r.FishBand * 1040, 28)));
                DrawLine(bar + new Vector2(r.FishCursor * 520, -5), bar + new Vector2(r.FishCursor * 520, 33), OceanView.Cream, 5, true);
                Text(p + new Vector2(25, 145), $"{Math.Max(0, 16 - r.FishingTime):0.0}s remaining                                      Esc · cancel cast", 18);
            }
            var boss = r.Enemies.FirstOrDefault(e => e.Kind == EnemyKind.Leviathan && e.Health > 0);
            if (boss != null)
            { Text(new(size.X / 2 - 85, 91), "THE CROWNCLAW", 23, true, OceanView.Coral); Bar(new(size.X / 2 - 200, 105), new(400, 9), boss.Health / boss.MaxHealth, OceanView.Coral); }
        }
        void CounterIcon(Vector2 center, int kind)
        {
            var ink = OceanView.Navy;
            if (kind == 0)
            {
                DrawCircle(center, 11, OceanView.Cream, false, 2, true);
                DrawLine(center, center + new Vector2(0, -7), OceanView.Cream, 2, true);
                DrawLine(center, center + new Vector2(5, 3), OceanView.Cream, 2, true);
                DrawCircle(center, 2, OceanView.Cream);
            }
            else if (kind is 1 or 2)
            {
                Color metal = new(kind == 1 ? "c5d4e2" : "f5cf79");
                if (kind == 1)
                {
                    Vector2[] rim = Enumerable.Range(0, 6).Select(i => center + Vector2.FromAngle(i * Mathf.Tau / 6) * 12).ToArray();
                    DrawColoredPolygon(rim, metal);
                }
                else DrawCircle(center, 12, metal);
                DrawCircle(center, 8, metal.Darkened(.3f), false, 1.5f, true);
                DrawColoredPolygon([center + new Vector2(0, -5), center + new Vector2(3, 0), center + new Vector2(0, 5), center + new Vector2(-3, 0)], ink);
                DrawArc(center, 10, Mathf.Pi, Mathf.Pi * 1.5f, 8, metal.Lightened(.3f), 1.5f, true);
            }
            else
            {
                DrawCircle(center + new Vector2(0, -2), 10, OceanView.Cream);
                DrawRect(new Rect2(center + new Vector2(-6, 4), new Vector2(12, 7)), OceanView.Cream);
                DrawCircle(center + new Vector2(-4, -2), 3, ink);
                DrawCircle(center + new Vector2(4, -2), 3, ink);
                DrawColoredPolygon([center + new Vector2(0, 1), center + new Vector2(-2, 5), center + new Vector2(2, 5)], ink);
                for (int x = -2; x <= 2; x += 4) DrawLine(center + new Vector2(x, 8), center + new Vector2(x, 11), ink, 1.5f);
            }
        }
        void DrawCompass(Vector2 size)
        {
            var r = Game.Run;
            var center = new Vector2(size.X - 100, 140);
            Color paper = new("e1d1a5"), ink = new("526963"), coast = new("a8ad7e");
            DrawCircle(center + new Vector2(0, 3), 82, new Color(OceanView.Navy, .3f));
            DrawCircle(center, 80, paper);
            DrawArc(center, 77, 0, Mathf.Tau, 64, ink, 1.5f, true);
            DrawArc(center, 63, 0, Mathf.Tau, 64, new Color(ink, .22f), 1, true);
            // A quiet compass rose keeps the chart north-up.
            for (int i = 0; i < 8; i++)
            {
                var direction = Vector2.FromAngle(i * Mathf.Tau / 8);
                DrawLine(center + direction * 12, center + direction * 59, new Color(ink, .15f), 1, true);
                DrawLine(center + direction * 71, center + direction * 75, ink, 1, true);
            }
            Text(center + new Vector2(-5, -64), "N", 13, true, ink);
            foreach (var place in r.World.Places)
            {
                if (!r.World.Discovered.Contains(place.Id)) continue;
                var offset = OceanView.G(place.Position - r.Position) / 17;
                if (offset.Length() > 56) continue;
                var at = center + offset;
                if (place.Kind == PlaceKind.Fishing)
                {
                    if (r.World.FishLeft(place) == 0) continue;
                    DrawArc(at, 4, .2f, Mathf.Pi - .2f, 10, ink, 1.5f, true);
                    DrawArc(at + new Vector2(0, 4), 4, .2f, Mathf.Pi - .2f, 10, ink, 1.5f, true);
                }
                else if (place.Kind == PlaceKind.Harbor) ChartAnchor(at, ink);
                else
                {
                    float radius = Math.Clamp(place.Radius / 17, 3, 11);
                    var outline = Enumerable.Range(0, 7).Select(i => at + Vector2.FromAngle(i * Mathf.Tau / 7) * radius * (i % 2 == 0 ? 1 : .8f)).ToArray();
                    DrawColoredPolygon(outline, coast);
                    DrawPolyline(outline.Append(outline[0]).ToArray(), ink, 1, true);
                }
            }
            var boss = r.Enemies.FirstOrDefault(e => e.Kind == EnemyKind.Leviathan && e.Health > 0);
            if (boss != null)
            {
                var d = OceanView.G(boss.Position - r.Position) / 17;
                if (d.Length() > 59) d = d.Normalized() * 59;
                DrawCircle(center + d, 4, new Color("b45143"));
            }
            var home = OceanView.G(new V2(-310, -220) - r.Position);
            if (home.Length() > 1000) ChartAnchor(center + home.Normalized() * 60, ink);
            Vector2[] pointer = [new(0, -8), new(-5, 6), new(0, 3), new(5, 6)];
            DrawColoredPolygon(pointer.Select(p => center + p.Rotated(r.Heading)).ToArray(), OceanView.Navy);
        }
        void ChartAnchor(Vector2 at, Color ink)
        {
            DrawCircle(at + new Vector2(0, -5), 2, ink, false, 1.5f, true);
            DrawLine(at + new Vector2(0, -3), at + new Vector2(0, 6), ink, 1.5f, true);
            DrawLine(at + new Vector2(-3, -1), at + new Vector2(3, -1), ink, 1.5f, true);
            DrawArc(at + new Vector2(0, 1), 5, 0, Mathf.Pi, 12, ink, 1.5f, true);
        }
    }
}
