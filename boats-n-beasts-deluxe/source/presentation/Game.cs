using Godot;
using BoatsNBeasts.Core;
using V2 = System.Numerics.Vector2;
namespace BoatsNBeasts;

public partial class Game : Node2D
{
    public Voyage Run = null!;
    OceanView3D ocean = null!;
    Vector2 uiPointer = new(-1000, -1000);
    V2? destination;
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
    string lootNotice = "";
    V2 lootNoticePosition;


    public override void _Ready()
    {
        bodyFont = ThemeDB.FallbackFont;
        titleFont = new SystemFont
        {
            FontNames = ["Georgia", "Times New Roman", "Liberation Serif", "DejaVu Serif"],
            FontWeight = 700
        };
        Run = new(selectedSeed, BoatKind.Cutter);
        ocean = new() { Voyage = Run, Menu = true }; AddChild(ocean);
        log.Load();
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
        if (!title && !controls && Run.IsActive)
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
            if (move != V2.Zero) destination = null;
            if (destination is V2 goal)
            {
                move = goal - Run.Position;
                if (move.LengthSquared() < 26 * 26) { destination = null; move = V2.Zero; }
                else move = Run.World.Avoid(Run.Position, OceanWorld.Unit(move), 65, 1);
            }
            Run.Tick(dt, new(move, boost, maneuverRequested));
            maneuverRequested = false;
        }

        ocean.Destination = destination;
        foreach (var e in Run.Events)
        {
            ocean.Effect(e);
            audio.Play(e.Kind);
            switch (e.Kind)
            {
                case "beacon": Toast($"Beacon lit · +{e.Value:0} XP"); break;
                case "comboFitted": Toast($"{Run.ActiveCombo!.Name} fitted"); break;
                case "towHooked": Toast("Tow secured · take the cargo to any beacon"); break;
                case "towSnapped": Toast("Towline snapped · sail back to the cargo"); break;
                case "towDelivered": Toast("Salvage delivered · refit earned"); break;
                case "chain": Toast($"{e.Value:0} beast chain · boost recharged"); break;
                case "boss": Toast("The Crownclaw rises"); break;
                case "enraged": Toast("Crownclaw is enraged · watch for charges"); break;
                case "hurt": hitNotice = .46f; break;
                case "treasure":
                case "heal":
                    lootNotice = $"+{e.Value:0} {(e.Kind == "heal" ? "hull" : "XP")}";
                    lootNoticePosition = e.Position;
                    lootNoticeTime = 1.2f;
                    break;
            }
        }
        Run.Events.Clear();
        ocean.Advance(dt);
        audio.InBattle = !title && Run.BossSpawned && !Run.BossSlain && Run.IsActive;

        if (!title && Run.SilverEarned > creditedSilver)
        {
            log.Earn(Run.SilverEarned - creditedSilver);
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
            if (!title && mouse.Pressed && hud.EquipmentAt(mouse.Position) >= 0)
            { GetViewport().SetInputAsHandled(); return; }
        }
        // Held boost input must not select an upgrade or retry after defeat.
        if (!title && input is InputEventKey key && key.PhysicalKeycode == Key.Space && Run.Mode != VoyageMode.Sailing) GetViewport().SetInputAsHandled();
    }
    public override void _UnhandledInput(InputEvent input)
    {
        if (input is InputEventMouseButton { Pressed: true, ButtonIndex: MouseButton.Left } click && !title && Run.Mode == VoyageMode.Sailing)
        {
            var point = hud.CourseAt(click.Position) ?? ocean.WorldPoint(click.Position);
            destination = Run.World.Slide(Run.Position, point, 70);
            usingController = false;
            GetViewport().SetInputAsHandled();
        }
        if (input is not InputEventJoypadButton { Pressed: true } button) return;
        if (button.ButtonIndex == JoyButton.X && !title && !controls && Run.IsActive)
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
        if (key.PhysicalKeycode == Key.E && !title && !controls && Run.IsActive)
        {
            maneuverRequested = true;
            GetViewport().SetInputAsHandled();
            return;
        }
        if (key.Keycode != Key.Escape) return;
        ToggleMenu();
        GetViewport().SetInputAsHandled();
    }

    void ToggleMenu()
    {
        if (controls) controls = false;
        else if (title) choosingBoat = journal = false;
        else if (Run.Mode == VoyageMode.Paused) Run.Mode = beforePause;
        else if (Run.Mode == VoyageMode.Sailing)
        {
            destination = null;
            beforePause = Run.Mode;
            Run.Mode = VoyageMode.Paused;
        }
        else return;
        BuildMenu();
    }

    public override void _Notification(int what)
    {
        if (what == NotificationApplicationFocusOut && Run != null && !title && Run.Mode == VoyageMode.Sailing)
        { beforePause = Run.Mode; destination = null; Run.Mode = VoyageMode.Paused; Callable.From(BuildMenu).CallDeferred(); }
    }
    void Start()
    {
        lootNoticeTime = hitNotice = 0;
        creditedSilver = 0; destination = null; toastTime = 0; maneuverRequested = false;
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
            Run = new(selectedSeed, selectedBoat, selectedCharter); ocean.Voyage = Run; ocean.Reset();
        }
        title = choosingBoat = runRecorded = controls = false;
        ocean.BeginSailing();
        if (log.Voyages == 0)
            Toast(usingController ? "Left stick to steer · RB to boost" : "WASD or click to steer · Space to boost");
        BuildMenu();
    }
    static void ReleaseMenuInput(Node node)
    {
        if (node is Control control) { control.MouseFilter = Control.MouseFilterEnum.Ignore; control.FocusMode = Control.FocusModeEnum.None; }
        foreach (var child in node.GetChildren()) ReleaseMenuInput(child);
    }
    void BackToTitle()
    {
        Record(); title = true; choosingBoat = controls = journal = false; destination = null; ocean.Menu = true;
        selectedSeed = (uint)Random.Shared.NextInt64(1, 1L << 32);
        Run = new(selectedSeed, selectedBoat, selectedCharter); ocean.Voyage = Run; ocean.Reset(); BuildMenu();
    }
    void Record()
    {
        if (title || runRecorded) return;
        log.Record(Run);
        runRecorded = true;
    }
    void Toast(string text) { toast = text; toastTime = 5; }
}
