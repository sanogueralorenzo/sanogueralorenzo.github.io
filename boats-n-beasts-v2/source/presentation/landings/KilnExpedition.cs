using BoatsNBeasts.Core;
using Godot;
using N2 = System.Numerics.Vector2;

namespace BoatsNBeasts;

public partial class KilnExpedition : CrewRun
{
    public CampaignOrder Order { get; set; } = FarLedger.Arcs[0].Orders.First(o => o.Ashore);
    public override int SilverEarned => Yard.Silver;
    internal int ChartTarget { get; private set; }
    internal bool ChartOpen { get; private set; }
    internal LandingYard Yard { get; private set; } = null!;
    internal NativeStage3D Stage { get; private set; } = null!;
    internal const float Floor = ShoreSculpture.Floor + .025f;
    Node3D captain = null!, mate = null!, district = null!, cargo = null!;
    MeshInstance3D silhouette = null!;
    readonly List<Node3D> loose = [];
    readonly List<(Node3D Boat, Vector3 Berth)> clayFleet = [];
    readonly Dictionary<YardBeastState, Node3D> models = [];
    readonly ImmediateMesh brush = new();
    readonly StandardMaterial3D ink = new()
    {
        ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded,
        VertexColorUseAsAlbedo = true,
        Transparency = BaseMaterial3D.TransparencyEnum.Alpha,
        CullMode = BaseMaterial3D.CullModeEnum.Disabled
    };
    YardHud hud = null!;
    YardWorkProps workProps = null!;
    AudioStreamPlayer cue = null!, hit = null!;
    int districtIndex = -1, pattern, oldHealth, oldSilver;
    bool repaired;
    float oldSwing, oldHook;
    N2 lastPlayer;
    bool hook, dodge, returned;
    public override void _Ready()
    {
        Yard = new(Order, Seed, Stores, Outfit);
        Stage = new(); AddChild(Stage);
        var overlay = new MeshInstance3D { Mesh = brush, ExtraCullMargin = 40, CastShadow = GeometryInstance3D.ShadowCastingSetting.Off }; Stage.AddChild(overlay);
        workProps = new(Stage, Point);
        captain = ActorArt3D.LandingParty(0); mate = ActorArt3D.LandingParty(1); Stage.AddChild(captain); Stage.AddChild(mate);
        var body = captain.GetChild<MeshInstance3D>(0);
        silhouette = new()
        {
            Mesh = body.Mesh,
            CastShadow = GeometryInstance3D.ShadowCastingSetting.Off,
            MaterialOverride = new StandardMaterial3D
            {
                ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded,
                NoDepthTest = true,
                Transparency = BaseMaterial3D.TransparencyEnum.Alpha,
                AlbedoColor = new("8be2d385"),
                RenderPriority = 3
            }
        };
        body.AddChild(silhouette);
        var canvas = new CanvasLayer(); AddChild(canvas); hud = new() { Trip = this }; canvas.AddChild(hud); hud.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        cue = new() { VolumeDb = -18 }; hit = new() { VolumeDb = -17 }; AddChild(cue); AddChild(hit); oldHealth = Yard.Health;
        Render();
    }
    public override void _PhysicsProcess(double delta)
    {
        if (returned || Yard.Phase == YardPhase.Lost || ChartOpen) return;
        N2 move = new((Down(Key.D) || Down(Key.Right) ? 1 : 0) - (Down(Key.A) || Down(Key.Left) ? 1 : 0), (Down(Key.S) || Down(Key.Down) ? 1 : 0) - (Down(Key.W) || Down(Key.Up) ? 1 : 0));
        Yard.Tick((float)delta, move, Down(Key.J) || Input.IsMouseButtonPressed(MouseButton.Left), dodge, hook); dodge = hook = false;
        Render(); if (Yard.Boarded) Settle(true);
    }
    static bool Down(Key k) => Input.IsPhysicalKeyPressed(k);
    public override void _UnhandledKeyInput(InputEvent input)
    {
        if (returned || input is not InputEventKey { Pressed: true, Echo: false } key) return;
        var k = key.PhysicalKeycode == Key.None ? key.Keycode : key.PhysicalKeycode;
        if ((k == Key.M || k == Key.Escape && ChartOpen) && Yard.Phase != YardPhase.Lost)
        { ChartOpen = !ChartOpen; hud.QueueRedraw(); GetViewport().SetInputAsHandled(); return; }
        if (ChartOpen)
        {
            if (k == Key.Tab) { ChartTarget++; hud.QueueRedraw(); GetViewport().SetInputAsHandled(); }
            return;
        }
        if (k == Key.E && Yard.Phase == YardPhase.Lost) { Settle(false); return; }
        if (Yard.Phase == YardPhase.Lost) return;
        if (k == Key.E) { var phase = Yard.Phase; Yard.Interact(); if (phase != Yard.Phase) Play(cue, 67, true); }
        else if (k == Key.Space) dodge = true;
        else if (k == Key.K) hook = true;
        else if (k is Key.Key1 or Key.Key2 or Key.Key3 or Key.Key4) Yard.Trade((int)k - (int)Key.Key1 + 1);
        else return;
        GetViewport().SetInputAsHandled();
    }
    void Settle(bool won)
    {
        if (returned) return;
        returned = true;
        if (Returned != null) Returned(won, Yard.Silver); else GetTree().ChangeSceneToFile("res://main.tscn");
    }
    public override void _ExitTree()
    {
        foreach (var player in new[] { cue, hit }) if (GodotObject.IsInstanceValid(player)) { player.Stop(); player.Stream = null; }
    }
    static void Play(AudioStreamPlayer player, int note, bool bell) { player.Stream = QuayTone.Note(note, bell); player.Play(); }
    internal Vector3 Point(N2 p, float lift = 0) => new(p.X, Floor + lift, p.Y);
    void Pose(Node3D n, N2 p, N2 facing, float lift = 0)
    {
        n.Position = Point(p, lift);
        if (facing.LengthSquared() > .01f) n.Rotation = new(0, MathF.Atan2(-facing.X, -facing.Y), 0);
    }
    void Render()
    {
        float t = Yard.Clock;
        if (districtIndex != Yard.District || repaired != Yard.Repaired)
        {
            district?.QueueFree(); district = YardScenery.District(Yard); Stage.AddChild(district);
            clayFleet.Clear();
            foreach (Node n in district.GetChildren())
                if (n is Node3D boat && boat.Name.ToString().StartsWith("ClayFerry", StringComparison.Ordinal)) clayFleet.Add((boat, boat.Position));
            districtIndex = Yard.District; repaired = Yard.Repaired;
        }
        var center = Yard.Player; Stage.Advance(t); Stage.Follow(new Vector2(center.X * 95, center.Y * 100 - 58), 8.65f);
        bool moving = N2.DistanceSquared(lastPlayer, Yard.Player) > .00001f; lastPlayer = Yard.Player;
        Pose(captain, Yard.Player, Yard.Heading, Yard.Dash > 0 ? .10f : moving ? Math.Abs(MathF.Sin(t * 12)) * .036f : 0);
        captain.GetChild<Node3D>(0).RotationDegrees = new(0, Yard.Swing * 158, 0);
        captain.Visible = Yard.Hurt <= 0 || (int)(Yard.Hurt * 25) % 2 == 0;
        Pose(mate, Yard.Mate, Yard.Hook > 0 ? Yard.HookEnd - Yard.Mate : Yard.Player - Yard.Mate, moving ? .032f * Math.Abs(MathF.Cos(t * 11)) : 0);
        silhouette.Visible = Yard.Foes.Any(f => f.Kind == YardBeast.Guardian && f.Position.Y > Yard.Player.Y && f.Position.Y - Yard.Player.Y < 2.3f && Math.Abs(f.Position.X - Yard.Player.X) < 1.2f);
        foreach (var gone in models.Keys.Where(k => !Yard.Foes.Contains(k)).ToArray()) { models[gone].QueueFree(); models.Remove(gone); }
        foreach (var f in Yard.Foes)
        {
            if (!models.TryGetValue(f, out var model)) { model = YardBeasts.Make(Yard.Region, f.Kind, Order); Stage.AddChild(model); models.Add(f, model); }
            Pose(model, f.Position, f.Heading);
            model.Rotation += new Vector3(f.Stagger * .11f, 0, f.Hit * .43f);
        }
        for (int i = 0; i < clayFleet.Count; i++)
        {
            var (boat, berth) = clayFleet[i];
            bool free = Order.Id == "cinder-kiln" && (Yard.Phase == YardPhase.Departure || Yard.Phase == YardPhase.Release && Yard.FinalIndex >= 2 && i == 0);
            var aim = berth + (free ? new Vector3(1.35f + i * .29f, 0, -.89f - i * .21f) : Vector3.Zero);
            boat.Position = boat.Position.Lerp(aim, .035f) with { Y = .09f + .022f * MathF.Sin(Yard.Clock * 1.8f + i) };
        }
        bool aboard = Yard.Phase == YardPhase.Departure && Yard.RescuedPassenger;
        if (Yard.Phase == YardPhase.Work && Yard.Job == LandingJob.Escort || Yard.Finishing && Yard.FinalStep.Action == LandingAction.Guide || aboard)
        {
            if (cargo == null) { cargo = ActorArt3D.LandingParty(2); Stage.AddChild(cargo); }
            if (aboard) Pose(cargo, Yard.Ferry + new N2(1.21f, .31f), -N2.UnitX, -.12f);
            else Pose(cargo, Yard.Passenger, Yard.Player - Yard.Passenger);
        }
        else if (cargo != null) { cargo.QueueFree(); cargo = null!; }
        while (loose.Count < Yard.SilverDrops.Count) { var b = new ActorGeometry(); b.Sphere(Vector3.Zero, new(.10f, .047f, .10f), new("d0eadc"), 8, 4); var c = ShoreSculpture.Bake(b); Stage.AddChild(c); loose.Add(c); }
        while (loose.Count > Yard.SilverDrops.Count) { loose[^1].QueueFree(); loose.RemoveAt(loose.Count - 1); }
        for (int i = 0; i < loose.Count; i++) loose[i].Position = Point(Yard.SilverDrops[i], .11f + .035f * MathF.Sin(t * 4 + i));
        int notes = Yard.Foes.Sum(f => f.Pattern);
        if (notes > pattern) Play(cue, Yard.Phase == YardPhase.Guardian ? 45 : 58, true);
        if (Yard.Hook > oldHook) Play(cue, 81, false);
        if (Yard.Health < oldHealth) Play(hit, 41, false);
        else if (Yard.Swing > oldSwing && Yard.Foes.Any(f => f.Hit > .10f)) Play(hit, 65, true);
        if (Yard.Silver > oldSilver) Play(cue, 77, true);
        pattern = notes; oldHook = Yard.Hook; oldSwing = Yard.Swing; oldHealth = Yard.Health; oldSilver = Yard.Silver;
        workProps.Sync(Yard); Marks(); hud.QueueRedraw();
    }
    internal IEnumerable<(N2 Position, string Name)> Locations()
    {
        if (!Yard.SpentStores && N2.DistanceSquared(Yard.Player, Yard.Plan.Pocket) < 10) yield return (Yard.Plan.Pocket, "E  Supply cache");
        if (Yard.BrokenBridge >= 0 && !Yard.Repaired && N2.DistanceSquared(Yard.Player, Yard.RepairPost) < 3f)
            yield return (Yard.RepairPost, "K  Splice bridge · 1 chit");
        switch (Yard.Phase)
        {
            case YardPhase.Fork:
            case YardPhase.Crossroads:
                for (int i = 0; i < 2; i++) if (!Yard.Completed[i]) yield return (Yard.Plan.Bells[i], $"{Yard.JobTitle(Yard.Options[i])}  ·  {2 + i} chits");
                if (Yard.Phase == YardPhase.Crossroads) yield return (Yard.Gate, "Freight gate");
                break;
            case YardPhase.Work:
                if (Yard.Carrying) yield return (Yard.Job == LandingJob.Weights ? Yard.ScaleSite : Yard.Delivery, "E  Deliver load");
                else if (Yard.Job == LandingJob.Capstans && !Yard.Anchored) yield return (Yard.Workbench, "K  Hold cable");
                else if (Yard.Job == LandingJob.Nets) { for (int i = 0; i < 3; i++) if (!Yard.Secured[i]) yield return (Yard.Float(i), "K  Net"); }
                else if (Yard.Job == LandingJob.Mould) { yield return (Yard.Billet, Yard.Region.Pin); yield return (Yard.Mould, "Mould"); }
                else if (Yard.Job == LandingJob.Escort) yield return (Yard.PassengerFree ? Yard.PassengerDock : Yard.Passenger, Yard.PassengerFree ? "Workers’ steps" : Yard.Region.Castaway);
                else for (int i = 0; i < 3; i++) if (!Yard.Secured[i]) yield return (Yard.Mark(i), Yard.Job == LandingJob.Breakers ? (i == 1 ? "K  Iron lid" : "J  Cargo lid") : Yard.Region.Marks[i]);
                break;
            case YardPhase.Camp: yield return (Yard.Camp, "Trade tarp"); yield return (Yard.Gate, Yard.District + 1 < Yard.LegCount ? "North ferry" : Order.Boss); break;
            case YardPhase.Guardian:
                if (Yard.Harness) for (int i = 0; i < 2; i++) if (Yard.GuardPins[i])
                    yield return (Yard.Locks[i], Yard.ChargeHarness ? (Yard.HotPins[i] ? "J  Hot pin" : "Draw charge") : (i == 0 ? "K  " : "J  ") + Yard.GuardFitting);
                break;
            case YardPhase.Keys:
            case YardPhase.Release:
                var step = Yard.FinalStep;
                if (step.Action == LandingAction.Guide) yield return (Yard.PassengerFree ? Yard.DeliverTo : Yard.Passenger, Yard.PassengerFree ? "Escort to steps" : "E  Help aboard");
                else if (step.Action == LandingAction.Brace && Yard.Braced) yield return (Yard.ReleaseLever, "E  Release lever");
                else
                {
                    string key = step.Action switch { LandingAction.Haul or LandingAction.Brace => "K", LandingAction.Cut or LandingAction.Seat => "J", _ => "E" };
                    yield return (Yard.FinalSite, key + "  " + step.Label);
                }
                if (step.Action == LandingAction.Seat) yield return (Yard.Billet, "Loose stop");
                break;
            case YardPhase.Departure: yield return (Yard.Ferry, "Board ferry"); break;
        }
    }
    void Marks()
    {
        brush.ClearSurfaces(); brush.SurfaceBegin(Mesh.PrimitiveType.Triangles, ink);
        Color green = new("8ce2c3"), gold = new("f3c87d"), rim = new("fff0ba");
        Arc(Yard.Player, .31f, .35f, 0, Mathf.Tau, green);
        foreach (var (p, _) in Locations()) Arc(p, .39f, .43f, 0, Mathf.Tau, gold);
        foreach (var f in Yard.Foes) if (f.Stagger > 0) Arc(f.Position, .47f, .52f, 0, Mathf.Tau, green);
        foreach (var a in Yard.Attacks)
        {
            var fill = a.Fired ? new Color("ffcc78bd") : new Color("e24a4788");
            float start = 0, span = Mathf.Tau, inner = a.Shape == AttackShape.Ring ? a.Inner : .01f;
            if (a.Shape == AttackShape.Lane)
            {
                var h = N2.Normalize(a.Target - a.Origin); var s = new N2(-h.Y, h.X) * a.Radius;
                Quad(a.Origin - s, a.Target - s, a.Target + s, a.Origin + s, fill);
                Stroke(a.Origin - s, a.Target - s, .022f, rim); Stroke(a.Origin + s, a.Target + s, .022f, rim);
                Arc(a.Origin, .01f, a.Radius, 0, Mathf.Tau, fill); Arc(a.Target, .01f, a.Radius, 0, Mathf.Tau, fill);
                var edge = N2.Lerp(a.Origin, a.Target, a.Windup); Stroke(edge - s, edge + s, .025f, gold); continue;
            }
            if (a.Shape == AttackShape.Fan) { var d = a.Target - a.Origin; span = 2 * MathF.Acos(a.Inner); start = MathF.Atan2(d.Y, d.X) - span * .5f; }
            Arc(a.Origin, inner, a.Radius, start, span, fill); Arc(a.Origin, a.Radius - .04f, a.Radius, start, span, rim);
            if (a.Shape == AttackShape.Ring) Arc(a.Origin, inner, inner + .04f, start, span, rim);
            float marker = Mathf.Lerp(inner, a.Radius, a.Windup); Arc(a.Origin, Math.Max(inner, marker - .035f), marker, start, span, gold);
        }
        if (Yard.Phase == YardPhase.Work)
        {
            if (Yard.Job == LandingJob.Capstans)
                for (int i = 0; i < 2; i++) Arc(Yard.WeightAt(i), .02f, .43f, 0, Mathf.Tau, new("db795dd8"));
            if (Yard.Job == LandingJob.Mould)
            {
                Arc(Yard.Billet, 0, .19f, 0, Mathf.Tau, new("d99053"), .12f);
                Arc(Yard.Mould, .23f, .39f, 0, Mathf.Tau, green);
            }
        }
        if (Yard.LiveHazard && Yard.HazardBeat < 2.76f)
        {
            Stroke(Yard.HazardStart, Yard.HazardEnd, .05f, gold);
            Arc(Yard.HazardPosition, .34f, .51f, 0, Mathf.Tau, Yard.HazardBeat < 1.60f ? gold : new Color("ef705e"));
        }
        if (Yard.Swing > 0) Arc(Yard.Player, .74f, .84f, MathF.Atan2(Yard.Heading.Y, Yard.Heading.X) - 1.21f, 2.42f, rim, .18f);
        if (Yard.Hook > 0) Stroke(Yard.Mate, Yard.HookEnd, .031f, gold, .51f);
        brush.SurfaceEnd();
    }
    void Stroke(N2 from, N2 to, float width, Color color, float lift = .044f)
    {
        var d = to - from; if (d.LengthSquared() < .0001f) return; var side = N2.Normalize(new(-d.Y, d.X)) * width;
        Quad(from - side, to - side, to + side, from + side, color, lift);
    }
    void Arc(N2 p, float inner, float outer, float start, float span, Color color, float lift = .045f)
    {
        if (outer <= inner) return;
        int count = Math.Max(5, (int)MathF.Ceiling(span * 7));
        for (int i = 0; i < count; i++)
        {
            float a = start + span * i / count, b = start + span * (i + 1) / count;
            N2 u = new(MathF.Cos(a), MathF.Sin(a)), v = new(MathF.Cos(b), MathF.Sin(b));
            Quad(p + u * inner, p + u * outer, p + v * outer, p + v * inner, color, lift);
        }
    }
    void Quad(N2 a, N2 b, N2 c, N2 d, Color color, float lift = .043f)
    {
        brush.SurfaceSetColor(color); brush.SurfaceAddVertex(Point(a, lift)); brush.SurfaceAddVertex(Point(b, lift)); brush.SurfaceAddVertex(Point(c, lift));
        brush.SurfaceAddVertex(Point(a, lift)); brush.SurfaceAddVertex(Point(c, lift)); brush.SurfaceAddVertex(Point(d, lift));
    }
}
