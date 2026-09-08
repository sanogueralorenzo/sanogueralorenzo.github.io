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
    Hud hud = null!;

    CanvasLayer layer = null!;
    Control menuRoot = null!;
    Font titleFont = null!, bodyFont = null!;
    bool title = true, settings, controls, reducedMotion, fullscreen, assistedFishing;
    BoatKind selectedBoat;
    VoyageMode shownMode = (VoyageMode)(-1), beforePause;
    LineEdit? seedInput;
    uint selectedSeed = 73919;
    int bestKills, completed;
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
            if (e.Kind == "bulwark") Toast("BULWARK · shots cleared, nearby beasts soaked");
            if (e.Kind == "boss") Toast("THE CROWNCLAW RISES  •  Keep moving. Watch the coral warning rings.");
            if (e.Kind == "bossSlain") Toast("THE SEA IS YOURS  •  Return to a harbor to finish your voyage.");
        }
        Run.Events.Clear(); ocean.Advance(dt); hud.QueueRedraw();
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
        string report = $"Mouse viewport={GetViewport().GetMousePosition()} global={GetGlobalMousePosition()} boatScreen={ocean.Screen(Run.Position)} viewportRect={GetViewportRect()}\nNative runtime capture: {name}\nRenderer: {RenderingServer.GetCurrentRenderingMethod()}\nSeed: {Run.World.Seed}\nMode: {Run.Mode}\nBoat: {Run.Boat}\nPosition: {Run.Position}\nHealth: {Run.Health}/{Run.MaxHealth}\nCoins: {Run.Coins}; cargo: {Run.Hold.Count}; charts: {Run.Charts}; kills: {Run.Kills}; level: {Run.Level}\nActive chunks: {Run.World.Loaded.Count}; enemies: {Run.Enemies.Count}; shots: {Run.Shots.Count}\nActual sailing seconds: {performanceClock:0.0}; peak enemies: {peakEnemyCount}; peak shots: {peakShotCount}\n";
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
        mouseHelm = boostLatched = false; destination = null; frameSamples.Clear(); performanceClock = lastPerformanceLog = 0; peakEnemyCount = peakShotCount = 0;
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
        if (Run.Mode == VoyageMode.Sailing || Run.Mode == VoyageMode.Fishing) return;
        var shade = new ColorRect { Color = new(0.015f, .06f, .16f, .66f), MouseFilter = Control.MouseFilterEnum.Stop }; shade.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect); menuRoot.AddChild(shade);
        VBoxContainer col;
        switch (Run.Mode)
        {
            case VoyageMode.Paused:
                col = Panel(510, "TAKE A BREATHER", "At anchor", "Your voyage is paused.");
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
                Record(); col = Panel(610, "A LEGEND COMES HOME", "The sea is yours", $"The Crownclaw is defeated. Your charts brought you home.\n{Run.Kills} beasts  •  {Run.Distance / 1000:0.0} leagues sailed  •  {Run.Coins} coins");
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
        col.AddChild(Label($"BEST {bestKills} BEASTS   •   {completed} VOYAGES WON", 16, false, new Color(OceanView.Cream, .55f)));
    }
    void ReadSeed() { if (seedInput != null && uint.TryParse(seedInput.Text, out uint value)) selectedSeed = value; seedInput = null; }
    void HarborMenu()
    {
        var col = Panel(950, "LIGHTHOUSE HARBOR  /  SAFE WATERS", "A little shore leave", $"{Run.Coins} coins   •   Hull {Run.Health:0}/{Run.MaxHealth:0}   •   Cargo {Run.Hold.Count}/12");
        col.AddThemeConstantOverride("separation", 7);
        var row = new HBoxContainer(); row.AddThemeConstantOverride("separation", 10); col.AddChild(row);
        row.AddChild(Button($"Sell catch · +{Run.Hold.Sum(f => f.Value)}", () => { Run.Sell(); BuildMenu(); }, true, Run.Hold.Count == 0));
        row.AddChild(Button($"Repair · {Run.RepairCost} coins", () => { Run.Repair(); BuildMenu(); }, false, Run.RepairCost == 0 || Run.Coins < Run.RepairCost));
        if (Run.BossSlain && !Run.Retired) row.AddChild(Button("Claim victory", () => { Run.ClaimVictory(); BuildMenu(); }, true));
        else row.AddChild(Button($"Switch to {(Run.Boat == BoatKind.Cutter ? "Trawler" : "Cutter")}", () => { Run.SwitchBoat(); BuildMenu(); }));
        col.AddChild(Label($"{Run.Spec.Ability} · {Run.Spec.Description}", 17, false, OceanView.Aqua));
        col.AddChild(Button(harborStats ? "SHOW WEAPONS  /  Ship upgrades selected" : "SHOW SHIP UPGRADES  /  Weapons selected", () => { harborStats = !harborStats; BuildMenu(); }));
        var grid = new GridContainer { Columns = 2 }; grid.AddThemeConstantOverride("h_separation", 14); grid.AddThemeConstantOverride("v_separation", 8); col.AddChild(grid);
        for (int i = harborStats ? 6 : 0; i < (harborStats ? Voyage.UpgradeNames.Length : 6); i++)
        {
            int option = i; var box = new VBoxContainer { CustomMinimumSize = new(438, 0) }; grid.AddChild(box);
            box.AddChild(Label(Voyage.UpgradeNames[i] + $"  {Run.Rank(i)}/5", 23, true)); box.AddChild(Label(Voyage.UpgradeDescriptions[i], 16));
            box.AddChild(Button(Run.Rank(i) >= 5 ? "Fully upgraded" : $"{(Run.Rank(i) == 0 ? "Install" : "Upgrade")} · {Run.UpgradeCost(i)} coins", () => { Run.Upgrade(option); BuildMenu(); }, false, Run.Rank(i) >= 5 || Run.Coins < Run.UpgradeCost(i)));
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
        if (Run.UpgradeChoices.Count == 0) col.AddChild(Button("All fitted · take 40 coins", () => { Run.Coins += 40; Run.Mode = VoyageMode.Sailing; BuildMenu(); }, true));
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
        bestKills = (int)cfg.GetValue("progress", "best_kills", 0); completed = (int)cfg.GetValue("progress", "wins", 0); ApplySettings();
    }
    void SaveSettings()
    {
        var cfg = new ConfigFile(); cfg.SetValue("display", "fullscreen", fullscreen); cfg.SetValue("display", "reduced_motion", reducedMotion); cfg.SetValue("accessibility", "toggle_boost", toggleBoost); cfg.SetValue("accessibility", "assisted_fishing", assistedFishing); cfg.SetValue("progress", "best_kills", bestKills); cfg.SetValue("progress", "wins", completed); cfg.Save("user://settings.cfg");
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
            DrawStyleBox(Game.Box(new Color(OceanView.Navy, .78f), 12), new Rect2(16, 16, 320, 146));
            string voyageStatus = $"{r.Position.Length() / 1000:0.00} LEAGUES   ·   {r.Coins} ◈";
            float statusWidth = Math.Max(266, TitleFont.GetStringSize(voyageStatus, fontSize: 24).X + 32);
            float statusLeft = size.X - statusWidth - 14;
            DrawStyleBox(Game.Box(new Color(OceanView.Navy, .78f), 12), new Rect2(statusLeft, 16, statusWidth, 76));
            Text(new(30, 44), "BOATS n BEASTS", 34, true);
            Text(new(32, 75), $"{r.Boat.ToString().ToUpperInvariant()}  /  LEVEL {r.Level}", 17);
            Bar(new(32, 91), new(210, 12), r.Health / r.MaxHealth, r.Health / r.MaxHealth < .3f ? OceanView.Coral : OceanView.Cream);
            Text(new(254, 104), $"{r.Health:0}/{r.MaxHealth:0}", 17);
            Bar(new(32, 116), new(210, 5), r.Boost / 100, OceanView.Aqua);
            Text(new(32, 145), r.Boat == BoatKind.Cutter ? (r.Slipstream > 0 ? "SLIPSTREAM · RAPID FIRE" : r.BoostExhausted ? (Game.toggleBoost ? "TAP BOOST TO REFILL" : "RELEASE BOOST TO REFILL") : "SLIPSTREAM · BOOST TO CHARGE") : $"BULWARK · {r.AbilityCharge * 100:0}%", 15, false, OceanView.Aqua);
            string zone = r.Safe ? "SAFE HARBOR" : r.Tier == 0 ? "SHELTERED SHOALS" : r.Tier < 3 ? "OPEN WATERS" : "THE DEEP BLUE";
            Text(new(size.X / 2 - 110, 43), zone, 26, true);
            Text(new(statusLeft + 16, 44), voyageStatus, 24, true);
            Text(new(statusLeft + 16, 75), $"CARGO {r.Hold.Count}/12   ·   CHART {r.Charts}/3", 18);
            string task = r.Retired ? "Voyage won · explore the endless ocean" : r.BossSlain ? "Return to a harbor · claim your victory" : r.Charts >= 3 ? "Sail beyond 3 leagues · hunt the Crownclaw" : "Fish 3 different schools beyond 1 league";
            Text(new(32, size.Y - 80), task, 20);
            for (int i = 0; i < r.Weapons.Length; i++)
            {
                var p = new Vector2(32 + i * 108, size.Y - 60); DrawStyleBox(Game.Box(new Color(OceanView.Navy, .7f), 8, new Color(OceanView.Cream, r.Weapons[i] > 0 ? .65f : .15f)), new(p, new Vector2(100, 38)));
                Text(p + new Vector2(10, 25), new[] { "CANNON", "HARPOON", "MORTAR", "COIL", "AURA", "SCATTER" }[i] + $" {r.Weapons[i]}", 15, true, new Color(OceanView.Cream, r.Weapons[i] > 0 ? 1 : .3f));
            }
            Text(new(size.X - 425, size.Y - 33), "WASD / CLICK SAIL   SPACE BOOST   ESC PAUSE", 16);
            Bar(new(0, size.Y - 4), new(size.X, 4), r.Xp / (float)r.NextXp, OceanView.Aqua);
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
        void DrawCompass(Vector2 size)
        {
            var r = Game.Run; var center = new Vector2(size.X - 94, 187); DrawCircle(center, 67, new Color(OceanView.Navy, .75f)); DrawArc(center, 67, 0, Mathf.Tau, 48, new Color(OceanView.Cream, .35f), 1, true); Text(center + new Vector2(-5, -74), "N", 17, true);
            foreach (var p in r.World.Places)
            {
                if (!r.World.Discovered.Contains(p.Id) || p.Kind is not (PlaceKind.Harbor or PlaceKind.Fishing)) continue;
                var offset = OceanView.G(p.Position - r.Position) / 17; if (offset.Length() > 60) continue;
                if (p.Kind == PlaceKind.Fishing && r.World.FishLeft(p) == 0) continue;
                DrawCircle(center + offset, p.Kind == PlaceKind.Harbor ? 4 : 2.5f, p.Kind == PlaceKind.Harbor ? OceanView.Cream : OceanView.Aqua);
            }
            var boss = r.Enemies.FirstOrDefault(e => e.Kind == EnemyKind.Leviathan && e.Health > 0);
            if (boss != null) { var d = OceanView.G(boss.Position-r.Position)/17; if (d.Length()>57) d=d.Normalized()*57; DrawCircle(center+d, 5, OceanView.Coral); }
            DrawColoredPolygon([center + new Vector2(0, -7), center + new Vector2(-4, 5), center + new Vector2(4, 5)], OceanView.Cream);
            // Home-bearing remains available even after its chunk unloads.
            var home = OceanView.G(new V2(-310, -220) - r.Position);
            if (home.Length() > 700) { var p = center + home.Normalized() * 57; DrawCircle(p, 4, OceanView.Cream); Text(center + new Vector2(-42, 87), "● HOME BEARING", 14); }
        }
    }
}
