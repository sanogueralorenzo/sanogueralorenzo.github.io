using BoatsNBeasts.Core;
using Godot;
using V2 = System.Numerics.Vector2;

namespace BoatsNBeasts;

public partial class SeaPassage : CrewRun
{
    public override int SilverEarned => Run?.Silver ?? 0;
    internal LanternPassage Run { get; private set; } = null!;
    internal NativeStage3D Stage { get; private set; } = null!;
    internal bool Paused { get; private set; }
    internal readonly List<V2> Wake = [];
    internal float Clock { get; private set; }
    Node3D boat = null!, hauler = null!, lockers = null!;
    SeaChart chart = null!;
    AudioStreamPlayer gunSound = null!, bellSound = null!, hookSound = null!;
    Node3D work = null!, tender = null!, tongue = null!, tow = null!, swivel = null!;
    readonly List<MeshInstance3D> floats = [];
    double wakeTimer;
    float beastHeading;
    Vector2 center;
    bool hooked, surged, patched, done;

    public override void _Ready()
    {
        Run = new(Seed, Stores);
        Stage = new() { Name = "LanternSound" };
        AddChild(Stage);
        boat = ActorArt3D.Boat(BoatKind.Cutter, [2, 0, 0, 0, 0, 0]);
        Stage.AddChild(boat);
        hauler = KeelwidowArt.Make(false);
        hauler.Name = "Lockerback";
        Stage.AddChild(hauler);
        foreach (var place in LanternPassage.Coast)
        {
            var island = EnvironmentArt3D.Build(place);
            Stage.AddChild(island);
            island.Position = NativeStage3D.Point(place.Position);
        }
        boat.AddChild(KeelwidowArt.Foam(.65f, 1.17f));
        lockers = new() { Name = "WatchFlags" };
        Stage.AddChild(lockers);
        foreach (bool repair in new[] { true, false })
        {
            var buoy = KeelwidowArt.Buoy(repair);
            lockers.AddChild(buoy);
            buoy.Position = NativeStage3D.Point(repair ? Run.RepairBuoy : Run.PowderBuoy);
        }
        tender = LanternCargo.Make("tender");
        tender.Name = "HushlightTender";
        Stage.AddChild(tender);
        tender.Position = NativeStage3D.Point(LanternPassage.Tender);
        tender.Rotation = new(0, -.83f, 0);
        tongue = LanternCargo.Make("tongue");
        tongue.Name = "BronzeTongue";
        Stage.AddChild(tongue);
        work = new() { Name = "WatchStation" };
        Stage.AddChild(work);
        tow = LanternCargo.Make("lifeboat");
        tow.Name = "Lifeboat";
        Stage.AddChild(tow);
        swivel = LanternCargo.Make("swivel");
        swivel.Name = "WatchGun";
        Stage.AddChild(swivel);
        foreach (var item in Run.Drift)
        {
            var marker = LanternCargo.Make(item.Coin ? "purse" : "powder drift");
            Stage.AddChild(marker);
            floats.Add(marker);
        }
        var layer = new CanvasLayer();
        AddChild(layer);
        chart = new() { Passage = this, MouseFilter = Control.MouseFilterEnum.Ignore };
        layer.AddChild(chart);
        chart.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        gunSound = Voice(91, .18f, true);
        bellSound = Voice(425, .68f, false);
        hookSound = Voice(250, .27f, false);
        Render(0);
    }

    AudioStreamPlayer Voice(int frequency, float length, bool thud)
    {
        const int rate = 22050;
        int samples = (int)(length * rate);
        var bytes = new byte[samples * 2];
        var noise = new Random(Seed);
        for (int i = 0; i < samples; i++)
        {
            float t = i / (float)rate;
            double phase = Math.Tau * frequency * t;
            double wave = thud ? Math.Sin(phase * (1.4 - t)) * .55 + (noise.NextDouble() - .5) * .65
                : Math.Sin(phase) * .55 + Math.Sin(phase * 2.48) * .27 + Math.Sin(phase * 4.07) * .12;
            short value = (short)(wave * Math.Min(t * 550, 1) * Math.Exp(-5 * t / length) * 28000);
            bytes[i * 2] = (byte)value;
            bytes[i * 2 + 1] = (byte)(value >> 8);
        }
        var player = new AudioStreamPlayer
        {
            Stream = new AudioStreamWav { Format = AudioStreamWav.FormatEnum.Format16Bits, MixRate = rate, Data = bytes },
            VolumeDb = -12
        };
        AddChild(player);
        return player;
    }

    public override void _UnhandledInput(InputEvent e)
    {
        if (done) return;
        var viewport = GetViewport();
        if (e is InputEventMouseButton { Pressed: true, ButtonIndex: MouseButton.Left } mouse && chart.ActionAt(mouse.Position))
        {
            viewport.SetInputAsHandled();
            return;
        }
        if (e is not InputEventKey { Pressed: true, Echo: false } k) return;
        var key = k.PhysicalKeycode == Key.None ? k.Keycode : k.PhysicalKeycode;
        if (key == Key.Escape && !Ended && Returned == null) Paused = !Paused;
        else if (key == Key.Enter && Ended) Finish();
        else if (key == Key.R && Paused) Finish();
        else if (key == Key.Enter && Paused) Paused = false;
        else if (key == Key.Q && !Paused) hooked = true;
        else if (key == Key.Shift && !Paused) surged = true;
        else if (key == Key.E && !Paused) patched = true;
        else return;
        viewport.SetInputAsHandled();
        if (!done) chart.QueueRedraw();
    }

    internal bool Ended => Run.Leg is PassageLeg.Recovered or PassageLeg.Wrecked;
    internal void Resume() { Paused = false; chart.QueueRedraw(); }
    internal void Finish()
    {
        if (done) return;
        done = true;
        if (Returned != null) Returned(Run.Leg == PassageLeg.Recovered, SilverEarned);
        else GetTree().ChangeSceneToFile("res://main.tscn");
    }

    public override void _PhysicsProcess(double delta)
    {
        if (done || Paused) return;
        float dt = (float)delta;
        var leg = Run.Leg;
        float flash = Run.GunFlash, hook = Run.HookFlash, wound = Run.WoundFlash;
        static bool KeyDown(Key a, Key b) => Input.IsPhysicalKeyPressed(a) || Input.IsPhysicalKeyPressed(b);
        V2 steer = new((KeyDown(Key.D, Key.Right) ? 1 : 0) - (KeyDown(Key.A, Key.Left) ? 1 : 0),
            (KeyDown(Key.S, Key.Down) ? 1 : 0) - (KeyDown(Key.W, Key.Up) ? 1 : 0));
        Run.Tick(dt, steer, Input.IsPhysicalKeyPressed(Key.Space), hooked, surged, patched);
        hooked = surged = patched = false;
        if (Run.GunFlash > flash) gunSound.Play();
        if (Run.HookFlash > hook) hookSound.Play();
        if (Run.WoundFlash > wound) { gunSound.PitchScale = .68f; gunSound.Play(); }
        else if (Run.GunFlash > flash) gunSound.PitchScale = 1;
        if (leg != Run.Leg)
        {
            bellSound.Play();
            if (Run.Leg == PassageLeg.Work)
                work.AddChild(LanternCargo.Make(Run.Rescue ? "castaway" : "powder"));
            if (Run.Leg == PassageLeg.Keelwidow)
            {
                hauler.QueueFree();
                hauler = KeelwidowArt.Make(true);
                hauler.Name = "Keelwidow";
                Stage.AddChild(hauler);
            }
        }
        Render(dt);
    }

    void Render(float dt)
    {
        Clock += dt;
        var goal = new Vector2(Run.Hull.X * .10f, Run.Center.Y + (Run.Hull.Y - Run.Center.Y) * .14f);
        if (!Run.Battle) goal = new(Run.Hull.X * .85f, Run.Hull.Y);
        center = center.Lerp(goal, 1 - MathF.Exp(-3 * dt));
        Stage.Follow(center);
        Stage.Advance(Clock);
        boat.Position = NativeStage3D.Point(Run.Hull);
        float heading = MathF.Atan2(Run.Bow.X, -Run.Bow.Y);
        boat.Rotation = new(0, -heading, 0);
        var direction = Run.Beast - Run.Hull;
        ActorArt3D.AnimateBoat(boat, Clock, Run.Velocity.Length() * .01f, heading - MathF.Atan2(direction.X, -direction.Y));
        hauler.Visible = Run.Battle;
        hauler.Position = NativeStage3D.Point(Run.Beast, MathF.Sin(Clock * 2) * .034f);
        var beastBow = Run.Move is HaulerMove.LiningUp or HaulerMove.Charging ? Run.Aim : -direction;
        beastHeading = Mathf.LerpAngle(beastHeading, -MathF.Atan2(beastBow.X, -beastBow.Y), Math.Min(1, 7 * dt));
        hauler.Rotation = new(Run.Move == HaulerMove.LiningUp ? Run.Windup * -.12f : 0, beastHeading, MathF.Sin(Clock * 2) * .018f);
        lockers.Visible = Run.Leg == PassageLeg.Salvage;
        work.Visible = Run.Leg == PassageLeg.Work;
        if (work.Visible) work.Position = NativeStage3D.Point(Run.WorkPosition, MathF.Sin(Clock * 2) * .032f);
        tow.Visible = Run.TowAboard;
        if (tow.Visible)
        {
            tow.Position = NativeStage3D.Point(Run.Tow);
            var pull = Run.Hull - Run.Tow;
            tow.Rotation = new(0, -MathF.Atan2(pull.X, -pull.Y), 0);
        }
        swivel.Visible = Run.GuardLive;
        if (swivel.Visible)
        {
            swivel.Position = NativeStage3D.Point(Run.Guard);
            var bearing = Run.Hull - Run.Guard;
            swivel.Rotation = new(0, -MathF.Atan2(bearing.X, -bearing.Y), 0);
        }
        tongue.Visible = Run.Leg == PassageLeg.Wreck;
        if (tongue.Visible) tongue.Position = NativeStage3D.Point(Run.Tongue, MathF.Sin(Clock * 2) * .032f);
        for (int i = 0; i < floats.Count; i++)
        {
            var marker = floats[i];
            var p = Run.DriftPosition(Run.Drift[i]);
            marker.Visible = !Run.Cleared.Contains(i) && !Run.Battle && Math.Abs(p.Y - center.Y) < 900;
            if (marker.Visible) marker.Position = NativeStage3D.Point(p, MathF.Sin(Clock * 2 + i) * .032f);
        }
        wakeTimer -= dt;
        if (wakeTimer <= 0)
        {
            wakeTimer = .07f;
            Wake.Insert(0, Run.Hull - Run.Bow * 69);
            if (Wake.Count > 17) Wake.RemoveAt(17);
        }
        chart.QueueRedraw();
    }
}
