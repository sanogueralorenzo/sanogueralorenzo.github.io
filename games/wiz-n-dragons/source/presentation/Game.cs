using Godot;
using WizNDragons.Core;
using V2 = System.Numerics.Vector2;
namespace WizNDragons;

public partial class Game : Node2D
{
    public Flight Run = null!;
    SkyView3D sky = null!;
    Vector2 uiPointer = new(-1000, -1000);
    V2? destination;
    readonly List<double> frameSamples = new();
    float performanceClock, lastPerformanceLog;
    double simulationMs;
    int peakEnemyCount, peakShotCount;
    int gameSpeed = 1;
    Hud hud = null!;

    CanvasLayer layer = null!;
    Control menuRoot = null!;
    Control? departingMenu;
    Font titleFont = null!, bodyFont = null!;
    bool title = true, choosingWizard, runRecorded, controls;
    WizardKind selectedWizard;
    FlightMode shownMode = (FlightMode)(-1), beforePause;
    uint selectedSeed = (uint)Random.Shared.NextInt64(1, 1L << 32);
    int bestKills, completed, finishedRuns, silver, creditedSilver;
    bool recorded;
    float elapsed, toastTime;
    string toast = "";
    float lootNoticeTime;
    string lootNotice = "";
    V2 lootNoticePosition;


    public override void _Ready()
    {
        bodyFont = ThemeDB.FallbackFont; titleFont = new FontVariation { BaseFont = ThemeDB.FallbackFont, VariationEmbolden = 1.0f };
        Run = new(selectedSeed, WizardKind.Ember);
        sky = new() { Flight = Run, Menu = true }; AddChild(sky);
        LoadProgress();
        layer = new(); AddChild(layer); hud = new() { Game = this, TitleFont = titleFont, BodyFont = bodyFont }; layer.AddChild(hud);
        GetWindow().Title = "Wiz ’n’ Dragons";
        BuildMenu();
        GD.Print("Wiz ’n’ Dragons | renderer=", RenderingServer.GetCurrentRenderingMethod(), " | seed=", selectedSeed);
    }
    public override void _Process(double delta)
    {
        if (!title && Run.Mode == FlightMode.Flying) { frameSamples.Add(delta * 1000); if(frameSamples.Count>7200)frameSamples.RemoveRange(0,3600); performanceClock += (float)delta; peakEnemyCount = Math.Max(peakEnemyCount, Run.Enemies.Count); peakShotCount = Math.Max(peakShotCount, Run.Shots.Count); }
        if (performanceClock-lastPerformanceLog>30) { lastPerformanceLog=performanceClock; var sorted=frameSamples.Order().ToArray(); GD.Print($"LIVE flyingSeconds={performanceClock:0} frameMeanMs={sorted.Average():0.00} p95Ms={sorted[(int)(sorted.Length*.95)]:0.00} chunks={Run.World.Loaded.Count} enemies={Run.Enemies.Count} shots={Run.Shots.Count} distance={Run.Distance:0} hp={Run.Health:0} combatSeconds={Run.CombatTime:0.0} populationTarget={Run.Director.Target(Run.CombatTime)} boss={Run.BossSpawned}"); }
        float dt = (float)Math.Min(delta, .05); elapsed += dt; toastTime = Math.Max(0, toastTime - dt);
        lootNoticeTime = Math.Max(0, lootNoticeTime - dt);
        // Repeat bounded simulation steps so faster time preserves collision and combat cadence.
        for (int step = 0; step < (title ? 1 : gameSpeed); step++)
        {
            if (!title && !controls)
            {
                V2 move = new((Down(Key.D) || Down(Key.Right) ? 1 : 0) - (Down(Key.A) || Down(Key.Left) ? 1 : 0), (Down(Key.S) || Down(Key.Down) ? 1 : 0) - (Down(Key.W) || Down(Key.Up) ? 1 : 0));
                if (move != V2.Zero) { destination = null; }
                if (destination is V2 goal) { var d = goal - Run.Position; if (d.Length() < 45) destination = null; else move = d; }
                var tickStart = System.Diagnostics.Stopwatch.GetTimestamp();
                Run.Tick(dt, new(move, (Down(Key.Space) || Down(Key.Shift))));
                if (Run.Mode == FlightMode.Flying) simulationMs = simulationMs * .95 + System.Diagnostics.Stopwatch.GetElapsedTime(tickStart).TotalMilliseconds * .05;
            }
            sky.Destination = destination;
            foreach (var e in Run.Events)
            {
                sky.Effect(e);
                if (e.Kind == "silver") Toast("+1 silver");
                if (e.Kind is "crystal" or "heal")
                {
                    lootNotice = $"+{e.Value:0} {(e.Kind == "heal" ? "health" : "XP")}"; lootNoticePosition = e.Position; lootNoticeTime = 1.2f;
                }
                if (e.Kind == "bulwark" && !bulwarkExplained) { bulwarkExplained = true; SaveProgress(); Toast("BULWARK · shots cleared, nearby beasts pushed away"); }
                if (e.Kind == "boss") Toast("THE ELDER DRAGON RISES  •  Keep moving.");
            }
            Run.Events.Clear(); sky.Advance(dt);
        }
        if (!title && Run.SilverEarned > creditedSilver)
        {
            int earnedSilver = Run.SilverEarned;
            silver += earnedSilver - creditedSilver; creditedSilver = earnedSilver; SaveProgress();
        }
        hud.QueueRedraw();
        if (!title && !controls && shownMode != Run.Mode) BuildMenu();
    }

    public override void _Input(InputEvent input)
    {
        if (input is InputEventMouseMotion motion) uiPointer = motion.Position;
        if (input is InputEventMouseButton mouse)
        {
            uiPointer = mouse.Position;
            if (!title && mouse.Pressed && hud.EquipmentAt(mouse.Position) >= 0)
            { GetViewport().SetInputAsHandled(); return; }
        }
        // Held boost input must not select an upgrade or retry after defeat.
        if (!title && input is InputEventKey key && key.PhysicalKeycode == Key.Space && Run.Mode != FlightMode.Flying) GetViewport().SetInputAsHandled();
    }
    public override void _UnhandledInput(InputEvent input)
    {
        if (input is InputEventMouseButton { Pressed: true, ButtonIndex: MouseButton.Left } click && !title && Run.Mode == FlightMode.Flying)
        { destination = sky.WorldPoint(click.Position); GetViewport().SetInputAsHandled(); }
    }
    bool capturing;
    async void CaptureReview()
    {
        if (capturing) return;
        capturing = true;
        await ToSignal(RenderingServer.Singleton, RenderingServer.SignalName.FramePostDraw);
        string folder = ProjectSettings.GlobalizePath("res://evidence"); System.IO.Directory.CreateDirectory(folder);
        string name = DateTime.Now.ToString("yyyyMMdd-HHmmss-fff") + "-" + (title ? "title" : Run.Mode.ToString().ToLowerInvariant());
        GetViewport().GetTexture().GetImage().SavePng(folder + "/" + name + ".png");
        var samples = frameSamples.Order().ToArray();
        string report = $"Mouse viewport={GetViewport().GetMousePosition()} global={GetGlobalMousePosition()} wizardScreen={sky.Screen(Run.Position)} viewportRect={GetViewportRect()}\nCamera projection={sky.Projection}; click world={sky.WorldPoint(GetViewport().GetMousePosition())}; destination={destination}\nNative runtime capture: {name}\nRenderer: {RenderingServer.GetCurrentRenderingMethod()}\nSeed: {Run.World.Seed}\nMode: {Run.Mode}\nGame speed: x{gameSpeed}\nFinished runs: {finishedRuns}; wizard selection: {choosingWizard}\nSilver: {silver}; earned this flight: {Run.SilverEarned}; next eligible combat time: {Run.NextSilverTime:R}\nWizard: {Run.Wizard}\nPosition: {Run.Position}\nHealth: {Run.Health}/{Run.MaxHealth}\nKills: {Run.Kills}; level: {Run.Level}; XP: {Run.Xp}/{Run.NextXp}; pending upgrades: {Run.PendingUpgrades}\nActive chunks: {Run.World.Loaded.Count}; enemies: {Run.Enemies.Count}; shots: {Run.Shots.Count}\nActual flying seconds: {performanceClock:0.0}; peak enemies: {peakEnemyCount}; peak shots: {peakShotCount}\n";
        report += $"Camera world={sky.Camera}; departure seconds={sky.DepartureTime:R}; menu opacity={(departingMenu != null && GodotObject.IsInstanceValid(departingMenu) ? departingMenu.Modulate.A : title ? 1 : 0):R}\n";
        report += $"Velocity={Run.Velocity}; boosting={Run.IsBoosting}; boost starts={Run.BoostStarts}; flow={Run.CurrentFlow}; current seconds={Run.CurrentRideTime}; crystal={Run.CrystalCollected}; potions={Run.PotionsBroken}; arcane casts={Run.ArcaneCasts}; runes={Run.RunesDropped}/{Run.RunesExploded}; ricochets={Run.FireballRicochets}; pulls={Run.TetherPulls}\n";
        report += $"Combat clock={Run.CombatTime:R}; director={Run.Director.Clock:R}/{Run.Director.Credits:R}; boost={Run.Boost:R}; invulnerable={Run.Invulnerable:R}; ability={Run.AbilityCharge:R}; fire rate={Run.FireRateMultiplier:R}\nSpell ranks={string.Join(",",Run.Spells)}; cooldowns={string.Join(",",Run.Cooldowns.Select(x=>x.ToString("R")))}\nDepletion={string.Join(";",Run.World.Depletion.Select(x=>$"{x.Key}={x.Value}"))}\n";
        report += $"Loot placement: crystals={Run.World.Places.Count(p => p.Kind == PlaceKind.Crystal)}; potions={Run.World.Places.Count(p => p.Kind == PlaceKind.Potion)}; depleted={Run.World.Depletion.Count}; visible encounter cache={sky.CachedEncounters}\n";
        foreach (var place in Run.World.Places.Where(p => p.Kind is PlaceKind.Crystal or PlaceKind.Potion))
            report += $"Loot {place.Id}: {place.Kind} position={place.Position} style={place.Style} heading={place.Heading:R} depleted={Run.World.Depletion.ContainsKey(place.Id)}\n";
        report += $"Boss bombs thrown={Run.BossBombsThrown}; explosions={Run.BossExplosions}; blast hits={Run.BossBlastHits}\n";
        report += $"Pacing regular target={Run.Director.Target(Run.CombatTime)}; income={Run.Director.Income(Run.CombatTime):R}; boss arrival seconds={SpawnDirector.BossArrivalSeconds:R}\n";
        report += $"Spark explosions={Run.SparkExplosions}; blast hits={Run.SparkBlastHits}\n";
        foreach (var enemy in Run.Enemies) report += $"Enemy {enemy.Id}: {enemy.Kind} position={enemy.Position} hp={enemy.Health:R} time={enemy.Time:R} attack={enemy.AttackClock:R} tell={enemy.Telegraph:R} dash={enemy.Dash:R} speedMultiplier={enemy.SpeedMultiplier:R} flightSpeed={enemy.FlightSpeed:R} fuse={enemy.Fuse:R}\n";
        foreach (var shot in Run.Shots) report += $"Shot {(shot.Hostile ? "Boss bomb" : shot.Kind.ToString())} hostile={shot.Hostile} position={shot.Position} life={shot.Life:R} target={shot.Target} age={shot.Age:R} flight={shot.FlightDuration:R}\n";
        report += $"CPU simulation average ms={simulationMs:0.000}; draw submission average ms={sky.DrawMs:0.000}; cached scenery={sky.CachedScenery}; engine FPS={Engine.GetFramesPerSecond()}; draw calls={Performance.GetMonitor(Performance.Monitor.RenderTotalDrawCallsInFrame)}; objects={Performance.GetMonitor(Performance.Monitor.RenderTotalObjectsInFrame)}\n";
        if (samples.Length > 0) report += $"Frame ms mean: {samples.Average():0.00}; p95: {samples[(int)(samples.Length*.95)]:0.00}; p99: {samples[(int)(samples.Length*.99)]:0.00}\n";
        System.IO.File.WriteAllText(folder + "/" + name + ".txt", report); GD.Print(report); capturing = false;
    }
    static bool Down(Key key) => Input.IsPhysicalKeyPressed(key);
    public override void _UnhandledKeyInput(InputEvent @event)
    {
        if (@event is not InputEventKey key || !key.Pressed || key.Echo) return;
        if (key.Keycode == Key.F12) { CaptureReview(); return; }
        if (key.Keycode == Key.Escape)
        {
            if (controls) { controls = false; BuildMenu(); }
            else if (title && choosingWizard) { choosingWizard = false; BuildMenu(); }
            else if (!title)
            {
                if (Run.Mode == FlightMode.Paused) Run.Mode = beforePause;
                else if (Run.Mode == FlightMode.Flying) { destination = null; beforePause = Run.Mode; Run.Mode = FlightMode.Paused; }
                BuildMenu();
            }
            GetViewport().SetInputAsHandled(); return;
        }
    }
    public override void _Notification(int what)
    {
        if (what == NotificationApplicationFocusOut && Run != null && !title && Run.Mode == FlightMode.Flying)
        { beforePause = Run.Mode; destination = null; Run.Mode = FlightMode.Paused; Callable.From(BuildMenu).CallDeferred(); }
    }
    void Start()
    {
        lootNoticeTime = 0;
        creditedSilver = 0; gameSpeed = 1; destination = null; frameSamples.Clear(); performanceClock = lastPerformanceLog = 0; peakEnemyCount = peakShotCount = 0;
        if (title)
        {
            // Keep the already-visible flight, meshes, wizard and animation clock.
            var fading = menuRoot; departingMenu = fading; menuRoot = null!;
            ReleaseMenuInput(fading);
            var fade = fading.CreateTween();
            fade.TweenProperty(fading, "modulate:a", 0f, .65).SetTrans(Tween.TransitionType.Sine);
            fade.TweenCallback(Callable.From(() => { fading.QueueFree(); if (departingMenu == fading) departingMenu = null; }));
        }
        else
        {
            // Defeat/victory retry is a fresh flight in the same starting geography.
            selectedSeed = (uint)Random.Shared.NextInt64(1, 1L << 32);
            Run = new(selectedSeed, selectedWizard); sky.Flight = Run; sky.Reset();
        }
        title = choosingWizard = runRecorded = controls = recorded = false;
        sky.BeginFlying();
        BuildMenu();
    }
    static void ReleaseMenuInput(Node node)
    {
        if (node is Control control) { control.MouseFilter = Control.MouseFilterEnum.Ignore; control.FocusMode = Control.FocusModeEnum.None; }
        foreach (var child in node.GetChildren()) ReleaseMenuInput(child);
    }
    void BackToTitle()
    {
        Record(); title = true; choosingWizard = controls = false; destination = null; sky.Menu = true;
        selectedSeed = (uint)Random.Shared.NextInt64(1, 1L << 32);
        Run = new(selectedSeed, selectedWizard); sky.Flight = Run; sky.Reset(); BuildMenu();
    }
    void Record()
    {
        if (title) return;
        if (!runRecorded) { finishedRuns++; runRecorded = true; }
        bestKills = Math.Max(bestKills, Run.Kills); if (Run.BossSlain && !recorded) { completed++; recorded = true; } SaveProgress();
    }
    bool bulwarkExplained;
    void Toast(string text) { toast = text; toastTime = 5; }
    StyleBoxFlat Box(Color bg, int radius = 14, Color? border = null)
    {
        var s = new StyleBoxFlat { BgColor = bg, CornerRadiusTopLeft = radius, CornerRadiusTopRight = radius, CornerRadiusBottomLeft = radius, CornerRadiusBottomRight = radius, ContentMarginLeft = 22, ContentMarginRight = 22, ContentMarginTop = 15, ContentMarginBottom = 15 };
        if (border != null) { s.BorderColor = border.Value; s.SetBorderWidthAll(2); } return s;
    }
    Label Label(string text, int size = 22, bool heading = false, Color? color = null)
    {
        var l = new Label { Text = text, AutowrapMode = TextServer.AutowrapMode.WordSmart };
        l.AddThemeFontOverride("font", heading ? titleFont : bodyFont); l.AddThemeFontSizeOverride("font_size", size); l.AddThemeColorOverride("font_color", color ?? MagicPalette.Cream); return l;
    }
    Button Button(string text, Action action, bool primary = false, bool disabled = false, bool purchase = false)
    {
        var b = new Button { Text = text, CustomMinimumSize = new(0, 46), Disabled = disabled, MouseDefaultCursorShape = Control.CursorShape.PointingHand };
        b.AddThemeFontOverride("font", bodyFont); b.AddThemeFontSizeOverride("font_size", 19);
        b.AddThemeColorOverride("font_color", primary ? MagicPalette.Navy : MagicPalette.Cream); b.AddThemeColorOverride("font_hover_color", MagicPalette.Navy); b.AddThemeColorOverride("font_focus_color", primary ? MagicPalette.Navy : MagicPalette.Cream); b.AddThemeColorOverride("font_pressed_color", MagicPalette.Navy); b.AddThemeColorOverride("font_disabled_color", new Color(MagicPalette.Cream, .34f));
        b.AddThemeStyleboxOverride("normal", Box(primary ? MagicPalette.Aqua : new Color("102e43"), 9, primary ? null : new Color("345064")));
        b.AddThemeStyleboxOverride("hover", Box(MagicPalette.Aqua, 9)); b.AddThemeStyleboxOverride("pressed", Box(MagicPalette.Aqua, 9)); b.AddThemeStyleboxOverride("focus", Box(new Color(0, 0, 0, 0), 9, MagicPalette.Aqua)); b.AddThemeStyleboxOverride("disabled", Box(new Color("102838"), 9));
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
    VBoxContainer Panel(float width, string eyebrow, string heading, string detail)
    {
        var center = new CenterContainer(); center.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect); menuRoot.AddChild(center);
        var panel = new PanelContainer { CustomMinimumSize = new(width, 0) }; panel.AddThemeStyleboxOverride("panel", Box(new Color("0a2233"), 12, new Color("345064"))); center.AddChild(panel);
        var column = new VBoxContainer(); column.AddThemeConstantOverride("separation", 14); panel.AddChild(column);
        column.AddChild(Label(eyebrow, 14, false, MagicPalette.Aqua)); column.AddChild(Label(heading, 32, true)); column.AddChild(Label(detail, 18));
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
        if (title) { if (choosingWizard) WizardMenu(); else TitleMenu(); FocusFirst(menuRoot); return; }
        if (Run.Mode == FlightMode.Flying)
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
            speed.AddThemeColorOverride("font_color", new Color(MagicPalette.Cream, .75f));
            speed.AddThemeStyleboxOverride("normal", Box(new Color(MagicPalette.Navy, .5f), 8));
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
            case FlightMode.Paused:
                col = Panel(510, "Paused", "Taking a breath", Run.BossSlain ? "Flight won · explore the endless sky" : Run.BossSpawned ? "Defeat the Elder Dragon to win." : $"Survive until {SpawnDirector.BossArrivalSeconds / 60:0}:00, then defeat the Elder Dragon.");
                col.AddChild(MenuAction("Resume flight", MenuGlyph.Fly, () => { Run.Mode = beforePause; BuildMenu(); }, true));
                col.AddChild(MenuAction("Spellbook", MenuGlyph.Book, () => { controls = true; BuildMenu(); }));
                col.AddChild(MenuAction("End flight · return to title", MenuGlyph.Home, BackToTitle)); break;
            case FlightMode.Upgrade: UpgradeMenu(); break;
            case FlightMode.Defeat:
                Record(); col = Panel(570, "Flight ended", "Lost in the clouds", $"{Run.Kills} beasts defeated  •  {Run.MaxDistance / 1000:0.0} sky leagues from home\nLevel {Run.Level}");
                col.AddChild(Label("Choose upgrades as you level up. Collect healing potions and boost to escape danger.", 20));
                col.AddChild(Button("Fly again", Start, true)); col.AddChild(Button("Choose another wizard", BackToTitle)); break;
            case FlightMode.Victory:
                Record(); col = Panel(610, "Flight complete", "The sky is yours", $"The Elder Dragon is defeated. The flight is won.\n{Run.Kills} beasts  •  {Run.Distance / 1000:0.0} sky leagues flown");
                col.AddChild(Button("Keep exploring the endless sky", () => { Run.Mode = FlightMode.Flying; BuildMenu(); }, true)); col.AddChild(Button("A new flight", BackToTitle)); break;
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
        var shade = new ColorRect { Color = new(0.015f, .06f, .16f, .3f), MouseFilter = Control.MouseFilterEnum.Ignore };
        shade.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect); menuRoot.AddChild(shade);
        var center = new CenterContainer(); center.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect); menuRoot.AddChild(center);
        var col = new VBoxContainer { CustomMinimumSize = new(380, 0) }; col.AddThemeConstantOverride("separation", 12); center.AddChild(col);
        var logo = Label("WIZ ’n’\nDRAGONS", 52, true); logo.HorizontalAlignment = HorizontalAlignment.Center;
        logo.AddThemeColorOverride("font_shadow_color", new Color("061c29")); logo.AddThemeConstantOverride("shadow_offset_y", 3);
        col.AddChild(logo);
        col.AddChild(new Control { CustomMinimumSize = new(0, 10), MouseFilter = Control.MouseFilterEnum.Ignore });
        col.AddChild(MenuAction("Play", MenuGlyph.Fly, () => { choosingWizard = true; BuildMenu(); }, true));



    }
    void WizardMenu()
    {
        var col = Panel(520, "New flight", "Choose your wizard", "One starting spell. One open slot.");
        var choices = new HBoxContainer(); choices.AddThemeConstantOverride("separation", 10); col.AddChild(choices);
        foreach (var wizard in Enum.GetValues<WizardKind>())
        {
            var choice = wizard;
            string name = WizardSpec.For(choice).Name;
            choices.AddChild(Button(selectedWizard == choice ? $"✓ {name}" : name, () => { selectedWizard = choice; Run = new(selectedSeed, choice); sky.Flight = Run; BuildMenu(); }, selectedWizard == choice));
        }
        var spec = WizardSpec.For(selectedWizard);
        col.AddChild(Label($"{spec.Ability}  •  {spec.Vitality} health\n{spec.Description}", 20, false, MagicPalette.Cream));
        col.AddChild(Button("Take flight", Start, true));
        col.AddChild(Button("Back", () => { choosingWizard = false; BuildMenu(); }));
    }
    void UpgradeMenu()
    {
        string category = Run.UpgradeChoices.Count == 0 ? "All fitted"
            : Run.UpgradeChoices[0] < Run.Spells.Length ? "Spells" : "Wizard upgrades";
        var col = Panel(700, $"Level {Run.Level}", category, "Choose one. Then keep flying.");
        foreach (int option in Run.UpgradeChoices) AddUpgradeRow(col, option);
        if (Run.UpgradeChoices.Count == 0) col.AddChild(Button("Restore 25 health", () => { Run.TakeUpgradeHeal(); BuildMenu(); }, true));
    }
    void AddUpgradeRow(VBoxContainer column, int option)
    {
        var button = Button("", () => { if (Run.Upgrade(option)) BuildMenu(); });
        button.CustomMinimumSize = new(0, 112);
        button.TooltipText = Flight.UpgradeNames[option];
        // Child content stays readable while the entire row handles mouse and keyboard input.
        button.AddThemeStyleboxOverride("hover", Box(new Color("194454"), 9, MagicPalette.Aqua));
        button.AddThemeStyleboxOverride("pressed", Box(new Color("205463"), 9, MagicPalette.Aqua));
        column.AddChild(button);
        var row = new HBoxContainer();
        row.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        row.OffsetLeft = row.OffsetTop = 16; row.OffsetRight = row.OffsetBottom = -16;
        row.AddThemeConstantOverride("separation", 18); button.AddChild(row);
        row.AddChild(new UpgradeSymbol { Kind = option, CustomMinimumSize = new(40, 40), SizeFlagsVertical = Control.SizeFlags.ShrinkCenter });
        var text = new VBoxContainer { SizeFlagsHorizontal = Control.SizeFlags.ExpandFill, SizeFlagsVertical = Control.SizeFlags.ShrinkCenter };
        text.AddThemeConstantOverride("separation", 6); row.AddChild(text);
        string rank = Run.Rank(option) == 0 ? "New" : $"Level {Run.Rank(option)} → {Run.Rank(option) + 1}";
        text.AddChild(Label($"{Flight.UpgradeNames[option]} · {rank}", 23, true));
        text.AddChild(Label(Run.UpgradeBenefit(option), 18));
        ReleaseMenuInput(row);
    }
    void ControlsMenu()
    {
        var col = Panel(900, "Spellbook", "A life in the sky", "Spells aim automatically. Keep moving and build your magic.");
        col.AddThemeConstantOverride("separation", 8);
        col.AddChild(Label("WASD / arrows     Fly in any direction\nLeft-click                 Fly to a point and stop\nSpace / Shift          Hold to boost while moving\nEsc                            Pause or resume", 19));
        col.AddChild(Label("Your flight", 25, true, MagicPalette.Aqua));
        col.AddChild(Label($"Fly through an endless sky. The camera follows you; crossing the screen never wraps you around. Clouds are scenery and never block your flight.\n\nDefeat creatures for XP. Level-ups alternate between spells and wizard upgrades, with at most three choices. Each wizard has two spell slots, including their starter. Potions restore up to 25 health; crystals grant 12 XP. Follow turquoise wind currents for a lift.\n\nEmber casts faster while boosting. Warden pulses every six seconds, clearing nearby enemy magic and pushing creatures away. Arcanist starts with homing orbs. Release boost after exhaustion to recharge.\n\nSurvive until {SpawnDirector.BossArrivalSeconds / 60:0}:00 and defeat the Elder Dragon. Menus pause combat. You can keep exploring after victory. Upgrades reset each flight; silver and records persist.", 19));
        col.AddChild(Button("Understood", () => { controls = false; BuildMenu(); }, true));
    }
    void LoadProgress()
    {
        var cfg = new ConfigFile(); if (cfg.Load("user://settings.cfg") != Error.Ok) return;
        bulwarkExplained = (bool)cfg.GetValue("tutorial", "bulwark_explained", false);
        silver = Math.Max(0, (int)cfg.GetValue("progress", "silver", 0));
        bestKills = (int)cfg.GetValue("progress", "best_kills", 0); completed = (int)cfg.GetValue("progress", "wins", 0);
        finishedRuns = Math.Max(0, (int)cfg.GetValue("progress", "finished_runs", completed));
    }
    void SaveProgress()
    {
        var cfg = new ConfigFile(); cfg.SetValue("tutorial", "bulwark_explained", bulwarkExplained); cfg.SetValue("progress", "best_kills", bestKills); cfg.SetValue("progress", "wins", completed); cfg.SetValue("progress", "silver", silver); cfg.SetValue("progress", "finished_runs", finishedRuns); cfg.Save("user://settings.cfg");
    }
    public partial class Hud : Node2D
    {
        public Game Game = null!; public Font TitleFont = null!, BodyFont = null!;
        void Text(Vector2 p, string text, int size = 22, bool heading = false, Color? color = null) => DrawString(heading ? TitleFont : BodyFont, p, text, HorizontalAlignment.Left, -1, size, color ?? MagicPalette.Cream);
        void Bar(Vector2 p, Vector2 size, float value, Color color)
        { DrawStyleBox(Game.Box(new Color(MagicPalette.Navy, .8f), 5), new(p, size)); DrawStyleBox(Game.Box(color, 5), new(p, new Vector2(size.X * Math.Clamp(value, 0, 1), size.Y))); }
        Rect2 EquipmentBounds(int slot, int count)
        {
            var size = GetViewportRect().Size;
            float rowWidth = count * 56 - 8;
            return new(new Vector2((size.X - rowWidth) / 2 + slot * 56, size.Y - 62), new Vector2(48, 48));
        }
        public int EquipmentAt(Vector2 pointer)
        {
            var equipped = Enumerable.Range(0, Flight.UpgradeNames.Length).Where(i => Game.Run.Rank(i) > 0).ToArray();
            for (int slot = 0; slot < equipped.Length; slot++)
                if (EquipmentBounds(slot, equipped.Length).HasPoint(pointer)) return equipped[slot];
            return -1;
        }
        public override void _Draw()
        {
            if (Game.title) return; var r = Game.Run; var size = GetViewportRect().Size;
            string level = $"LVL {r.Level}";
            var levelPosition = new Vector2(size.X - 14 - TitleFont.GetStringSize(level, fontSize: 20).X, 30);
            Text(levelPosition, level, 20, true, MagicPalette.Cream);
            int seconds = (int)r.CombatTime;
            string[] counters = [$"{seconds / 60:00}:{seconds % 60:00}", Game.silver.ToString(), r.Kills.ToString()];
            float countersWidth = counters.Sum(value => BodyFont.GetStringSize(value, fontSize: 21).X + 48) + 12;
            DrawStyleBox(Game.Box(new Color(MagicPalette.Navy, .55f), 8), new Rect2(14, 16, countersWidth, 44));
            float counterX = 38;
            for (int i = 0; i < counters.Length; i++)
            {
                CounterIcon(new(counterX, 38), i);
                Text(new(counterX + 20, 45), counters[i], 21);
                counterX += BodyFont.GetStringSize(counters[i], fontSize: 21).X + 48;
            }
            var healthPosition = Game.sky.ElevatedScreen(r.Position, 1.9f) + new Vector2(-24, -17);
            Bar(healthPosition, new(48, 6), r.Health / r.MaxHealth, new Color("ed4b55"));
            foreach (var enemy in r.Enemies.Where(e => e.Health < e.MaxHealth && e.Kind != EnemyKind.ElderDragon))
            {
                var at = Game.sky.ElevatedScreen(enemy.Position, enemy.Kind == EnemyKind.Drake ? 1.1f : .55f) + new Vector2(-17, -8);
                Bar(at, new(34, 4), enemy.Health / enemy.MaxHealth, MagicPalette.Coral);
            }
            if (Game.lootNoticeTime > 0 && r.IsActive)
            {
                float alpha = Math.Min(1, Game.lootNoticeTime / .4f);
                float width = BodyFont.GetStringSize(Game.lootNotice, fontSize: 21).X;
                var at = Game.sky.Screen(Game.lootNoticePosition) + new Vector2(-width / 2, -35 - (1.2f - Game.lootNoticeTime) * 24);
                Text(at + Vector2.One, Game.lootNotice, 21, true, new Color(MagicPalette.Navy, alpha));
                Text(at, Game.lootNotice, 21, true, new Color(MagicPalette.Cream, alpha));
            }
            if (r.IsBoosting || r.Boost < 100)
            {
                var boostAt = Game.sky.Screen(r.Position) + new Vector2(0, 36);
                DrawArc(boostAt, 16, .15f, Mathf.Pi - .15f, 24, r.BoostExhausted ? new Color(MagicPalette.Coral, .7f) : new Color(MagicPalette.Navy, .9f), 5, true);
                DrawArc(boostAt, 16, .15f, .15f + (Mathf.Pi - .3f) * Math.Max(.015f, r.Boost / 100), 24, r.BoostExhausted ? MagicPalette.Coral : MagicPalette.Aqua, 3, true);
                if (r.BoostExhausted)
                {
                    DrawStyleBox(Game.Box(new Color(MagicPalette.Navy, .9f), 5), new(boostAt + new Vector2(-55, 20), new Vector2(110, 23)));
                    Text(boostAt + new Vector2(-46, 36), "Release boost", 13);
                }
            }
            var equipped = Enumerable.Range(0, Flight.UpgradeNames.Length).Where(i => r.Rank(i) > 0).ToArray();
            for (int slot = 0; slot < equipped.Length; slot++)
            {
                int item = equipped[slot];
                var bounds = EquipmentBounds(slot, equipped.Length);
                var p = bounds.Position;
                DrawStyleBox(Game.Box(new Color(MagicPalette.Navy, .65f), 6), bounds);
                DrawSetTransform(p + new Vector2(4, 2));
                UpgradeSymbol.DrawSymbol(this, item, MagicPalette.Aqua);
                DrawSetTransform(Vector2.Zero);
                DrawCircle(p + new Vector2(42, 40), 10, MagicPalette.Navy);
                Text(p + new Vector2(38, 45), r.Rank(item).ToString(), 13, true);
                if (bounds.HasPoint(Game.uiPointer))
                {
                    string name = $"{Flight.UpgradeNames[item]} · Rank {r.Rank(item)}";
                    string detail = Flight.UpgradeDescriptions[item];
                    float width = Math.Max(BodyFont.GetStringSize(detail, fontSize: 16).X, 220) + 28;
                    var at = new Vector2(Math.Clamp(p.X + 24 - width / 2, 12, size.X - width - 12), p.Y - 75);
                    DrawStyleBox(Game.Box(new Color(MagicPalette.Navy, .95f), 8), new(at, new Vector2(width, 64)));
                    Text(at + new Vector2(14, 24), name, 17, true);
                    Text(at + new Vector2(14, 48), detail, 16);
                }
            }
            Bar(Vector2.Zero, new(size.X, 8), r.Xp / (float)r.NextXp, MagicPalette.Aqua);
            if (Game.toastTime > 0) { float width = BodyFont.GetStringSize(Game.toast, fontSize: 20).X; DrawStyleBox(Game.Box(new Color(MagicPalette.Navy, .9f), 10), new((size.X - width) / 2 - 20, 144, width + 40, 45)); Text(new((size.X - width) / 2, 174), Game.toast, 20); }
            var boss = r.Enemies.FirstOrDefault(e => e.Kind == EnemyKind.ElderDragon && e.Health > 0);
            if (boss != null)
            { Text(new(size.X / 2 - 85, 91), "THE ELDER DRAGON", 23, true, MagicPalette.Coral); Bar(new(size.X / 2 - 200, 105), new(400, 9), boss.Health / boss.MaxHealth, MagicPalette.Coral); }
        }
        void CounterIcon(Vector2 center, int kind)
        {
            var ink = MagicPalette.Navy;
            if (kind == 0)
            {
                DrawCircle(center, 11, MagicPalette.Cream, false, 2, true);
                DrawLine(center, center + new Vector2(0, -7), MagicPalette.Cream, 2, true);
                DrawLine(center, center + new Vector2(5, 3), MagicPalette.Cream, 2, true);
                DrawCircle(center, 2, MagicPalette.Cream);
            }
            else if (kind == 1)
            {
                Color metal = new("c5d4e2");
                Vector2[] rim = Enumerable.Range(0, 6).Select(i => center + Vector2.FromAngle(i * Mathf.Tau / 6) * 12).ToArray();
                DrawColoredPolygon(rim, metal);
                DrawCircle(center, 8, metal.Darkened(.3f), false, 1.5f, true);
                DrawColoredPolygon([center + new Vector2(0, -5), center + new Vector2(3, 0), center + new Vector2(0, 5), center + new Vector2(-3, 0)], ink);
                DrawArc(center, 10, Mathf.Pi, Mathf.Pi * 1.5f, 8, metal.Lightened(.3f), 1.5f, true);
            }
            else
            {
                DrawCircle(center + new Vector2(0, -2), 10, MagicPalette.Cream);
                DrawRect(new Rect2(center + new Vector2(-6, 4), new Vector2(12, 7)), MagicPalette.Cream);
                DrawCircle(center + new Vector2(-4, -2), 3, ink);
                DrawCircle(center + new Vector2(4, -2), 3, ink);
                DrawColoredPolygon([center + new Vector2(0, 1), center + new Vector2(-2, 5), center + new Vector2(2, 5)], ink);
                for (int x = -2; x <= 2; x += 4) DrawLine(center + new Vector2(x, 8), center + new Vector2(x, 11), ink, 1.5f);
            }
        }
    }
}
