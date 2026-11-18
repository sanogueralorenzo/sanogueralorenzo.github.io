using Godot;
using BoatsNBeasts.Core;
using V2 = System.Numerics.Vector2;
namespace BoatsNBeasts;

public partial class Game : Node2D
{
    public Voyage Run = null!;
    OceanView3D ocean = null!;
    Vector2 uiPointer = new(-1000, -1000);
    readonly SailCourse course = new();
    Hud hud = null!;

    CanvasLayer layer = null!;
    Control menuRoot = null!;
    Control? departingMenu;
    Font titleFont = null!, bodyFont = null!;
    bool usingController;
    bool title = true, choosingBoat, journal, runRecorded, controls, maneuverRequested;
    BoatKind selectedBoat;
    Charter selectedCharter;
    VoyageMode shownMode = (VoyageMode)(-1), beforePause;
    uint selectedSeed = (uint)Random.Shared.NextInt64(1, 1L << 32);
    readonly CaptainLog log = new();
    SeaAudio audio = null!;
    int creditedSilver;
    float toastTime;
    string toast = "";
    float lootNoticeTime, hitNotice;
    float lootNoticeAltitude;
    float pairingFlash;
    string lootNotice = "";
    V2 lootNoticePosition;
    Color lootNoticeColor = NauticalPalette.Cream;


    public override void _Ready()
    {
        bodyFont = ThemeDB.FallbackFont;
        titleFont = new SystemFont
        {
            FontNames = ["Georgia", "Times New Roman", "Liberation Serif", "DejaVu Serif"],
            FontWeight = 700
        };
        Run = new(selectedSeed, BoatKind.Cutter);
        log.Load();
        ocean = new() { Voyage = Run, Course = course, Menu = true, Livery = log.Livery }; AddChild(ocean);
        audio = new() { Muted = log.Muted }; AddChild(audio);
        layer = new(); AddChild(layer); hud = new() { Game = this, TitleFont = titleFont, BodyFont = bodyFont }; layer.AddChild(hud);
        GetWindow().Title = "Boats ’n’ Beasts Deluxe";
        BuildMenu();
        GD.Print("Boats ’n’ Beasts | renderer=", RenderingServer.GetCurrentRenderingMethod(), " | seed=", selectedSeed);
    }
    public override void _Process(double delta)
    {
        float dt = (float)Math.Min(delta, .05);
        toastTime = Math.Max(0, toastTime - dt);
        lootNoticeTime = Math.Max(0, lootNoticeTime - dt);
        hitNotice = Math.Max(0, hitNotice - dt);
        pairingFlash = Math.Max(0, pairingFlash - dt);
        if (chartOpen) PanChart(dt);
        if (!title && !controls && !chartOpen && Run.IsActive)
        {
            V2 move = new((Down(Key.D) || Down(Key.Right) ? 1 : 0) - (Down(Key.A) || Down(Key.Left) ? 1 : 0),
                (Down(Key.S) || Down(Key.Down) ? 1 : 0) - (Down(Key.W) || Down(Key.Up) ? 1 : 0));
            bool boost = Down(Key.Space) || Down(Key.Shift);
            foreach (int device in Input.GetConnectedJoypads())
            {
                var stick = new V2(Input.GetJoyAxis(device, JoyAxis.LeftX), Input.GetJoyAxis(device, JoyAxis.LeftY));
                if (stick.LengthSquared() > .16f)
                {
                    usingController = true;
                    move = V2.Normalize(stick) * Math.Clamp((stick.Length() - .4f) / .6f, 0, 1);
                }
                boost |= Input.IsJoyButtonPressed(device, JoyButton.RightShoulder);
            }
            Run.Tick(dt, course.Apply(Run, new(move, boost, maneuverRequested)));
            maneuverRequested = false;
        }

        if (Run.Mode is VoyageMode.Victory or VoyageMode.Defeat) course.Clear();
        foreach (var e in Run.Events)
        {
            ocean.Effect(e);
            audio.Play(e.Kind);
            switch (e.Kind)
            {
                case "beacon": Toast($"Beacon lit · +{e.Value:0} XP"); break;
                case "comboFitted": Toast($"{WeaponCombo.ForUpgrade((int)e.Value)!.Name} fitted"); break;
                case "weaponSwapped": Toast($"{Voyage.UpgradeNames[(int)e.Value]} fitted"); break;
                case "stormshot":
                case "tripwire":
                case "riptide":
                    pairingFlash = .9f;
                    break;
                case "towHooked": Toast(Run.PremiumSalvageBeacon != null
                    ? "Tow secured · choose a buyer" : "Tow secured · take the cargo to any beacon"); break;
                case "towSnapped": Toast("Towline snapped · sail back to the cargo"); break;
                case "towDelivered":
                    int salvagerSail = log.EarnSails(Run);
                    earnedSails |= salvagerSail;
                    Toast(e.Value > 0 ? $"Premium salvage · +{e.Value:0} silver bonus"
                        : salvagerSail != 0 ? $"Salvage delivered · {SailDesign.For(SailLivery.WreckDiver).Name} sail unlocked"
                        : "Salvage delivered · refit earned");
                    break;
                case "chain": Toast($"{e.Value:0} beast chain · boost recharged"); break;
                case "boss": Toast("The Crownclaw rises"); break;
                case "enraged": Toast("Crownclaw is enraged · watch for charges"); break;
                case "repairInterrupted": Toast("Repairs interrupted · berth still available"); break;
                case "repairDone": Toast("Harbor repairs complete"); break;
                case "cacheCaught": Toast($"Cache secured · +{e.Value:0} XP"); break;
                case "stormKills": Toast(e.Value == 1 ? "Lightning took a beast" : $"Lightning took {e.Value:0} beasts"); break;
                case "stormCrewKill": LootNotice(e, "Storm kill", NauticalPalette.Lightning, .6f); break;
                case "hurt": hitNotice = .46f; break;
                case "closeCall":
                    LootNotice(e, e.Value >= 1 ? $"Close call · +{e.Value:0} boost" : "Close call", NauticalPalette.Gold,
                        ActorArt3D.BoatHudHeight);
                    break;
                case "treasure":
                case "heal":
                    LootNotice(e, $"+{e.Value:0} {(e.Kind == "heal" ? "hull" : "XP")}", NauticalPalette.Cream);
                    break;
            }
        }
        Run.Events.Clear();
        if (!chartOpen) ocean.Advance(dt);
        audio.Voyage = title ? null : Run;
        audio.Ducked = !title && (chartOpen || controls || !Run.IsActive);

        if (!title && Run.SilverEarned > creditedSilver)
        {
            log.Earn(Run.SilverEarned - creditedSilver, Run.BeaconsLit > 0);
            creditedSilver = Run.SilverEarned;
        }
        hud.QueueRedraw();
        if (!title && !controls && shownMode != Run.Mode) BuildMenu();
    }

    public override void _Input(InputEvent input)
    {
        if (input is InputEventMouseMotion motion) uiPointer = motion.Position;
        if (input is InputEventKey { Pressed: true }) usingController = false;
        if (input is InputEventJoypadButton { Pressed: true }) usingController = true;
        if (input is InputEventMouseButton mouse)
        {
            uiPointer = mouse.Position;
            if (!title && !chartOpen && mouse.Pressed && hud.EquipmentAt(mouse.Position) >= 0)
            { GetViewport().SetInputAsHandled(); return; }
        }
        // Held boost input must not select an upgrade or retry after defeat.
        if (!title && input is InputEventKey key && key.PhysicalKeycode == Key.Space && Run.Mode != VoyageMode.Sailing) GetViewport().SetInputAsHandled();
    }
    public override void _UnhandledInput(InputEvent input)
    {
        if (input is InputEventMouseButton { Pressed: true } click && !title && Run.Mode == VoyageMode.Sailing)
        {
            if (chartOpen || click.ButtonIndex == MouseButton.Left && hud.ChartToggle.HasPoint(click.Position))
            {
                if (chartOpen) HandleChartClick(click);
                else ToggleChart();
                GetViewport().SetInputAsHandled();
                return;
            }
            if (click.ButtonIndex == MouseButton.Right)
            {
                ClearChartCourse();
                GetViewport().SetInputAsHandled();
            }
            else if (click.ButtonIndex == MouseButton.Left)
            {
                bool interacted = (hud.HuntSignalControl.HasPoint(click.Position) || hud.RepairControl.HasPoint(click.Position)) &&
                    TryVoyageInteraction();
                if (!interacted && !PlotChartOrder(hud.CourseAt(click.Position) ?? new(ocean.WorldPoint(click.Position))))
                    Toast("Choose a course through open water");
                usingController = false;
                GetViewport().SetInputAsHandled();
            }
        }
        if (input is not InputEventJoypadButton { Pressed: true } button) return;
        if (chartOpen) HandleChartButton(button.ButtonIndex);
        else if (button.ButtonIndex == JoyButton.B && pendingSwap.HasValue) ToggleMenu();
        else if (button.ButtonIndex == JoyButton.Y && CanOpenChart) ToggleChart();
        else if (button.ButtonIndex == JoyButton.A)
        {
            if (!TryVoyageInteraction()) return;
        }
        else if (button.ButtonIndex == JoyButton.X && !title && !controls && Run.IsActive)
            maneuverRequested = true;
        else if (button.ButtonIndex == JoyButton.Start)
            ToggleMenu();
        else return;
        GetViewport().SetInputAsHandled();
    }
    static bool Down(Key key) => Input.IsPhysicalKeyPressed(key);
    public override void _UnhandledKeyInput(InputEvent @event)
    {
        if (@event is not InputEventKey key || !key.Pressed || key.Echo) return;
        if (chartOpen || key.Keycode == Key.Tab && CanOpenChart)
        {
            if (key.Keycode is Key.Tab or Key.Escape) ToggleChart();
            else if (key.Keycode == Key.Equal) ZoomChart(1);
            else if (key.Keycode == Key.Minus) ZoomChart(-1);
            GetViewport().SetInputAsHandled();
            return;
        }
        if (key.PhysicalKeycode == Key.E && !title && !controls && Run.IsActive)
        {
            maneuverRequested = true;
            GetViewport().SetInputAsHandled();
            return;
        }
        if (key.PhysicalKeycode == Key.F && TryVoyageInteraction())
        {
            GetViewport().SetInputAsHandled();
            return;
        }
        if (key.Keycode != Key.Escape) return;
        ToggleMenu();
        GetViewport().SetInputAsHandled();
    }

    bool TryVoyageInteraction()
    {
        if (title || controls || !Run.IsActive) return false;
        if (!Run.TrySignalCrownclaw() && !(Run.AtRepairBerth && Run.ToggleHarborRepairs())) return false;
        course.Clear();
        return true;
    }

    void ToggleMenu()
    {
        if (controls) controls = false;
        else if (sailLocker) CloseSailLocker();
        else if (title)
        {
            if (choosingBoat) CloseDeparture();
            else journal = false;
        }
        else if (pendingSwap.HasValue) pendingSwap = null;
        else if (Run.Mode == VoyageMode.Paused) Run.Mode = beforePause;
        else if (Run.Mode == VoyageMode.Sailing)
        {
            course.Clear();
            beforePause = Run.Mode;
            Run.Mode = VoyageMode.Paused;
        }
        else return;
        BuildMenu();
    }

    public override void _Notification(int what)
    {
        if (what == NotificationApplicationFocusOut && Run != null && !title && Run.Mode == VoyageMode.Sailing)
        {
            chartOpen = false;
            beforePause = Run.Mode;
            course.Clear();
            Run.Mode = VoyageMode.Paused;
            Callable.From(BuildMenu).CallDeferred();
        }
    }
    void Start()
    {
        lootNoticeTime = hitNotice = pairingFlash = 0;
        pendingSwap = null;
        previewCharter = null;
        replayingHunt = null;
        chartOpen = false;
        dailyBonus = earnedSails = 0;
        previousBest = 0;
        creditedSilver = 0; course.Clear(); toastTime = 0; maneuverRequested = false;
        if (title)
        {
            // Keep the already-visible voyage, meshes, boat and animation clock.
            var fading = menuRoot; departingMenu = fading; menuRoot = null!;
            ReleaseMenuInput(fading);
            var fade = fading.CreateTween();
            fade.TweenProperty(fading, "modulate:a", 0f, .65).SetTrans(Tween.TransitionType.Sine);
            fade.TweenCallback(Callable.From(() => { fading.QueueFree(); if (departingMenu == fading) departingMenu = null; }));
        }
        else
        {
            Run = new(Run.World.Seed, Run.Boat, Run.Charter); ocean.Voyage = Run; ocean.Reset();
        }
        title = choosingBoat = runRecorded = controls = journal = false;
        ocean.BeginSailing();
        BuildMenu();
    }
    static void ReleaseMenuInput(Node node)
    {
        if (node is Control control) { control.MouseFilter = Control.MouseFilterEnum.Ignore; control.FocusMode = Control.FocusModeEnum.None; }
        foreach (var child in node.GetChildren()) ReleaseMenuInput(child);
    }
    void PreviewRun(uint seed, BoatKind boat, Charter charter)
    {
        bool newGeography = seed != Run.World.Seed;
        Run = new(seed, boat, charter);
        ocean.Voyage = Run;
        if (newGeography) ocean.Reset();
    }

    void BackToTitle() => ReturnToHarbor(false);

    void ReturnToHarbor(bool chooseBoat)
    {
        Record(); title = true; choosingBoat = chooseBoat; controls = journal = false; course.Clear(); ocean.Menu = true;
        daily = null;
        selectedSeed = (uint)Random.Shared.NextInt64(1, 1L << 32);
        Run = new(selectedSeed, selectedBoat, selectedCharter); ocean.Voyage = Run; ocean.Reset(); BuildMenu();
    }
    void Record()
    {
        if (title || runRecorded) return;
        previousBest = daily is { } challenge ? log.DailyTime(challenge.Day) : log.BestTime(Run.Boat, Run.Charter);
        var result = log.Record(Run, daily);
        dailyBonus = result.DailyBonus;
        earnedSails |= result.NewSails;
        runRecorded = true;
    }
    void Toast(string text) { toast = text; toastTime = 5; }

    void LootNotice(GameEvent ev, string text, Color color, float altitude = 0)
    {
        lootNotice = text;
        lootNoticePosition = ev.Position;
        lootNoticeColor = color;
        lootNoticeAltitude = altitude;
        lootNoticeTime = 1.2f;
    }
}
