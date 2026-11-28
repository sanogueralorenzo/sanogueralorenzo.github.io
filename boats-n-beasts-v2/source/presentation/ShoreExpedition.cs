using Godot;
using BoatsNBeasts.Core;
using V2 = System.Numerics.Vector2;

namespace BoatsNBeasts;

public partial class ShoreExpedition : CrewRun
{
    public override int SilverEarned => Fight.Silver;
    internal ShoreFight Fight { get; private set; } = null!;
    internal NativeStage3D Stage { get; private set; } = null!;
    internal bool Paused { get; private set; }
    internal float VoiceUntil { get; private set; }
    Node3D captain = null!, mate = null!, skiff = null!;
    Node3D? survivor;
    readonly MeshInstance3D[] floats = new MeshInstance3D[2];
    MeshInstance3D billet = null!, mould = null!;
    AudioStreamPlayer metal = null!, line = null!, hit = null!;
    float oldSwing, oldHook;
    int lastPattern, lastHealth, oldSilver;
    V2 lastPosition;
    MeshInstance3D silhouette = null!;
    ShoreHud hud = null!;
    MeshInstance3D marks = null!;
    readonly List<Node3D> coins = [];
    readonly Dictionary<ShoreFoe, Node3D> foes = [];
    readonly MeshInstance3D[] bells = new MeshInstance3D[2];
    readonly bool[] bellState = new bool[2];
    readonly ImmediateMesh traces = new();
    readonly StandardMaterial3D paint = new()
    {
        ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded,
        VertexColorUseAsAlbedo = true,
        Transparency = BaseMaterial3D.TransparencyEnum.Alpha,
        CullMode = BaseMaterial3D.CullModeEnum.Disabled
    };
    ArrayMesh coinMesh = null!;
    bool dodge, hook, returned;
    Button? resumeButton, leaveButton;
    const float Ground = ShoreSculpture.Floor + .017f;

    public override void _Ready()
    {
        Fight = new(Seed, Stores);
        Stage = new(); AddChild(Stage); Stage.AddChild(ShoreSculpture.Quay(Seed));
        var upper = ShoreSculpture.Quay(unchecked(Seed + 177), true);
        upper.Position = new(QuayPaths.Summit.X, 0, QuayPaths.Summit.Y); Stage.AddChild(upper);
        for (int i = 0; i < 2; i++)
        {
            var station = ShoreSculpture.Station(i);
            station.Position = new(ShoreFight.Bells[i].X, 0, ShoreFight.Bells[i].Y); Stage.AddChild(station);
            var post = ShoreSculpture.WindingPost(); post.Position = Point(QuayPaths.Anchors[i]); Stage.AddChild(post);
        }
        foreach (var (from, to) in QuayPaths.Bridges) Stage.AddChild(ShoreSculpture.Causeway(from, to));
        for (int i = 0; i < 2; i++) { floats[i] = ShoreSculpture.NetFloat(); Stage.AddChild(floats[i]); }
        billet = ShoreSculpture.BronzeBlank(); Stage.AddChild(billet);
        mould = ShoreSculpture.CastingMould(); mould.Position = Point(ShoreFight.Mould); Stage.AddChild(mould);
        metal = Voice(-17); line = Voice(-20); hit = Voice(-19); lastHealth = Fight.Health;
        captain = ActorArt3D.LandingParty(0); Stage.AddChild(captain);
        var body = captain.GetChild<MeshInstance3D>(0);
        silhouette = new()
        {
            Mesh = body.Mesh,
            MaterialOverride = new StandardMaterial3D
            {
                ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded,
                Transparency = BaseMaterial3D.TransparencyEnum.Alpha,
                NoDepthTest = true,
                AlbedoColor = new("a3e9da82"),
                RenderPriority = 3
            },
            CastShadow = GeometryInstance3D.ShadowCastingSetting.Off
        };
        body.AddChild(silhouette);
        mate = ActorArt3D.LandingParty(1); Stage.AddChild(mate);
        skiff = ActorArt3D.ShoreSkiff();
        skiff.Position = new(-3.65f, .03f, 4.46f); skiff.RotationDegrees = new(0, 24, 0);
        Stage.AddChild(skiff);
        for (int i = 0; i < bells.Length; i++) SetBell(i);
        var token = new ActorGeometry(); token.Sphere(Vector3.Zero, new(.11f, .05f, .11f), new("d0e8dd"), 8, 4);
        token.Ring(new(0, .025f, 0), .08f, .013f, new("758f93")); coinMesh = token.Mesh(DioramaSurface.Material);
        marks = new() { Mesh = traces, CastShadow = GeometryInstance3D.ShadowCastingSetting.Off, ExtraCullMargin = 12 };
        Stage.AddChild(marks);
        var layer = new CanvasLayer(); AddChild(layer);
        hud = new() { Shore = this }; layer.AddChild(hud); hud.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        VoiceUntil = 7;
        Sync();
    }
    AudioStreamPlayer Voice(float db)
    {
        var player = new AudioStreamPlayer { VolumeDb = db, MaxPolyphony = 3 }; AddChild(player); return player;
    }
    static void Play(AudioStreamPlayer player, int midi, bool bell)
    {
        player.Stream = QuayTone.Note(midi, bell); player.Play();
    }
    public override void _PhysicsProcess(double delta)
    {
        if (Paused || returned || Fight.Phase == QuayPhase.Lost && leaveButton != null) return;
        float dt = (float)delta;
        V2 move = new((Down(Key.D) || Down(Key.Right) ? 1 : 0) - (Down(Key.A) || Down(Key.Left) ? 1 : 0),
            (Down(Key.S) || Down(Key.Down) ? 1 : 0) - (Down(Key.W) || Down(Key.Up) ? 1 : 0));
        string previousVoice = Fight.Voice;
        Fight.Tick(dt, move, Down(Key.J) || Input.IsMouseButtonPressed(MouseButton.Left), dodge, hook);
        dodge = hook = false;
        if (previousVoice != Fight.Voice) VoiceUntil = Fight.Clock + 3.7f;
        Sync();
        if (Fight.Boarded) Return(true);
        else if (Fight.Phase == QuayPhase.Lost && leaveButton == null) ShowChoices(false);
    }
    static bool Down(Key key) => Input.IsPhysicalKeyPressed(key);
    public override void _UnhandledKeyInput(InputEvent input)
    {
        if (returned || input is not InputEventKey { Pressed: true, Echo: false } k) return;
        var key = k.PhysicalKeycode == Key.None ? k.Keycode : k.PhysicalKeycode;
        if (key == Key.Escape && Returned == null && Fight.Phase != QuayPhase.Lost) { if (Paused) Resume(); else ShowChoices(true); }
        else if (Paused || Fight.Phase == QuayPhase.Lost) return;
        else if (key == Key.K) hook = true;
        else if (key == Key.Space) dodge = true;
        else if (key == Key.E)
        {
            var phase = Fight.Phase;
            string prior = Fight.Voice;
            Fight.Interact();
            if (Fight.Voice != prior) VoiceUntil = Fight.Clock + 4.8f;
            if (Fight.Phase != phase) Play(metal, Fight.Phase == QuayPhase.Warden ? 48 : 69, true);
        }
        else return;
        GetViewport().SetInputAsHandled();
    }
    void ShowChoices(bool pause)
    {
        Paused = pause;
        if (pause) resumeButton = Choice("Resume expedition", -28, Resume);
        leaveButton = Choice(pause ? "Retreat to harbor" : "Return to harbor", pause ? 34 : 0, () => Return(false));
        (resumeButton ?? leaveButton).GrabFocus(); hud.QueueRedraw();
    }
    Button Choice(string text, int offset, Action action)
    {
        var b = new Button { Text = text };
        hud.AddChild(b); b.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.Center);
        b.OffsetLeft = -150; b.OffsetRight = 150; b.OffsetTop = offset; b.OffsetBottom = offset + 48;
        b.AddThemeFontSizeOverride("font_size", 22); b.Pressed += action;
        return b;
    }
    void Resume()
    {
        Paused = false; resumeButton?.QueueFree(); leaveButton?.QueueFree();
        resumeButton = leaveButton = null; hud.QueueRedraw();
    }
    public override void _ExitTree()
    {
        foreach (var voice in new[] { metal, line, hit })
            if (GodotObject.IsInstanceValid(voice)) { voice.Stop(); voice.Stream = null; }
    }
    void Return(bool success)
    {
        if (returned) return;
        returned = true;
        if (Returned != null) Returned(success, Fight.Silver);
        else GetTree().ChangeSceneToFile("res://main.tscn");
    }
    void SetBell(int i)
    {
        bells[i]?.QueueFree(); bells[i] = ShoreSculpture.SignalBell(Fight.Rung[i]); Stage.AddChild(bells[i]);
        bells[i].Position = Point(ShoreFight.Bells[i]); bellState[i] = Fight.Rung[i];
    }
    internal static Vector3 Point(V2 p, float lift = 0) => new(p.X, Ground + lift, p.Y);
    void Sync()
    {
        float t = Fight.Clock;
        Stage.Advance(t);
        Stage.Follow(new Vector2(Fight.Player.X * 85, Fight.Player.Y * 100 - 65), 8.4f);
        bool walking = V2.DistanceSquared(lastPosition, Fight.Player) > .00001f;
        float step = walking ? .037f * MathF.Abs(MathF.Sin(t * 12)) : 0;
        lastPosition = Fight.Player;
        SetActor(captain, Fight.Player, Fight.Facing, Fight.Dash > 0 ? .10f : step);
        SetActor(mate, Fight.Crew, Fight.Hook > 0 ? Fight.HookEnd - Fight.Crew : Fight.Player - Fight.Crew, walking ? .034f * MathF.Abs(MathF.Cos(t * 11)) : 0);
        captain.Visible = Fight.Hurt <= 0 || (int)(Fight.Hurt * 27) % 2 == 0;
        captain.GetChild<Node3D>(0).RotationDegrees = new(0, Fight.Swung * 156 - Fight.Dash * 80, 0);
        silhouette.Visible = Fight.Foes.Any(f => f.Warden && Fight.Player.Y < f.Position.Y
            && MathF.Abs(Fight.Player.X - f.Position.X) < 1.2f && f.Position.Y - Fight.Player.Y < 2.2f);
        ActorArt3D.Animate(skiff, t, 0);
        if (Fight.Phase is QuayPhase.Rescue or QuayPhase.Homeward)
        {
            if (survivor == null)
            {
                survivor = ActorArt3D.NellSpindle(); Stage.AddChild(survivor);
            }
            SetActor(survivor, Fight.Keeper, Fight.Player - Fight.Keeper, 0);
        }
        for (int i = 0; i < bells.Length; i++) if (bellState[i] != Fight.Rung[i]) SetBell(i);
        foreach (var gone in foes.Keys.Where(f => !Fight.Foes.Contains(f)).ToArray()) { foes[gone].QueueFree(); foes.Remove(gone); }
        foreach (var f in Fight.Foes)
        {
            if (!foes.TryGetValue(f, out var model))
            {
                model = ShoreSculpture.Keeper(f.Warden);
                if (f.Mortar) { model.Scale *= new Vector3(.90f, 1.27f, .90f); model.AddChild(MortarPlume()); }
                Stage.AddChild(model); foes.Add(f, model);
            }
            SetActor(model, f.Position, f.Aim, f.Strike * .35f);
            var tilt = model.Rotation;
            tilt.X = f.Warning > 0 ? -.13f * MathF.Sin((1 - f.Warning / f.Winding) * Mathf.Pi * .65f) : f.Stagger * .16f;
            tilt.Z = f.Flash * .48f;
            model.Rotation = tilt;
        }
        while (coins.Count < Fight.Coins.Count) { var c = new MeshInstance3D { Mesh = coinMesh }; Stage.AddChild(c); coins.Add(c); }
        while (coins.Count > Fight.Coins.Count) { coins[^1].QueueFree(); coins.RemoveAt(coins.Count - 1); }
        for (int i = 0; i < coins.Count; i++) coins[i].Position = Point(Fight.Coins[i], .12f + .04f * MathF.Sin(t * 4 + i));
        billet.Visible = Fight.Phase == QuayPhase.Foundry;
        if (billet.Visible) billet.Position = Point(Fight.Billet);
        mould.Visible = Fight.Phase == QuayPhase.Foundry;
        for (int i = 0; i < 2; i++)
        {
            floats[i].Visible = Fight.Phase == QuayPhase.Fishery && !Fight.Floats[i];
            var p = Fight.FloatAt(i); floats[i].Position = new(p.X, .09f + .045f * MathF.Sin(t * 3 + i), p.Y);
        }
        int pattern = Fight.Foes.Sum(f => f.Pattern);
        if (pattern > lastPattern) Play(metal, Fight.Phase == QuayPhase.Warden ? 47 : 61, true);
        if (Fight.Hook > oldHook) Play(line, 83, false);
        if (Fight.Health < lastHealth) Play(hit, 43, false);
        else if (Fight.Hurt == 0 && Fight.Swung > oldSwing && (Fight.Foes.Any(f => f.Flash > .12f) || billet.Visible)) Play(hit, 66, true);
        if (Fight.Silver > oldSilver) Play(line, 79, true);
        lastPattern = pattern; oldHook = Fight.Hook; oldSwing = Fight.Swung; oldSilver = Fight.Silver; lastHealth = Fight.Health;
        DrawMarks(); hud.QueueRedraw();
    }
    static MeshInstance3D MortarPlume()
    {
        var b = new ActorGeometry();
        for (int i = -1; i <= 1; i++)
            b.Tube([new(0, 1.76f, .12f), new(i * .30f, 2.27f, .13f), new(i * .43f, 2.35f, .26f)], [.13f, .09f, .015f], new("b64d46"), 6);
        return ShoreSculpture.Bake(b);
    }
    static void SetActor(Node3D actor, V2 position, V2 heading, float lift)
    {
        actor.Position = Point(position, lift);
        if (heading.LengthSquared() > .001f) actor.Rotation = new(0, MathF.Atan2(-heading.X, -heading.Y), 0);
    }
    void DrawMarks()
    {
        traces.ClearSurfaces(); traces.SurfaceBegin(Mesh.PrimitiveType.Triangles, paint);
        Color mint = new("7bebcf"), amber = new("ffcc79"), chalk = new("fff3cc");
        Arc(Fight.Player, .31f, .35f, 0, Mathf.Tau, mint);
        foreach (var f in Fight.Foes)
        {
            if (f.Stagger > 0) Arc(f.Position, f.Warden ? .84f : .45f, f.Warden ? .88f : .49f, 0, Mathf.Tau, mint);
            if (f.Warning == 0 && f.Strike == 0) continue;
            var center = f.Stroke == BellStroke.Fall ? f.Target : f.Position;
            float a = MathF.Atan2(f.Aim.Y, f.Aim.X), spread = f.Stroke == BellStroke.Sweep ? MathF.Acos(f.SweepCos) : Mathf.Pi;
            float outer = f.Stroke switch { BellStroke.Fall => 1.32f, BellStroke.Toll => 3.5f, _ => f.Reach };
            float inner = f.Stroke == BellStroke.Toll ? 1.48f : .015f;
            var color = f.Strike > 0 ? new Color("ffdf89ae") : new Color("f04d4e76");
            Arc(center, inner, outer, a - spread, 2 * spread, color);
            Arc(center, outer - .042f, outer, a - spread, 2 * spread, chalk);
            if (inner > 1) Arc(center, inner, inner + .042f, a - spread, 2 * spread, chalk);
            float fill = Mathf.Lerp(inner, outer, 1 - f.Warning / f.Winding);
            Arc(center, MathF.Max(inner, fill - .042f), fill, a - spread, 2 * spread, amber);
        }
        if (Fight.Swung > 0)
        {
            float angle = MathF.Atan2(Fight.Facing.Y, Fight.Facing.X);
            Arc(Fight.Player, .72f, .81f, angle - 1.25f, 2.50f, chalk, .17f);
        }
        if (Fight.Hook > 0)
        {
            var d = Fight.HookEnd - Fight.Crew;
            if (d.LengthSquared() > .0001f)
            {
                var side = V2.Normalize(new(-d.Y, d.X)) * .025f;
                Quad(Fight.Crew + side, Fight.HookEnd + side, Fight.HookEnd - side, Fight.Crew - side, amber, .51f);
            }
        }
        for (int i = 0; i < 2; i++) if (!Fight.Rung[i] && Fight.Phase is QuayPhase.Belfry or QuayPhase.Fork)
            Arc(ShoreFight.Bells[i], .39f, .43f, 0, Mathf.Tau, amber);
        if (Fight.Phase == QuayPhase.Foundry)
        {
            Arc(Fight.Billet, .29f, .33f, 0, Mathf.Tau, amber);
            Arc(ShoreFight.Mould, .44f, .49f, 0, Mathf.Tau, mint);
        }
        if (Fight.Phase == QuayPhase.Ascent) Arc(QuayPaths.Belfry, .43f, .5f, 0, Mathf.Tau, amber);
        if (Fight.Bound)
        {
            for (int i = 0; i < 2; i++)
            {
                if (!Fight.Chains[i]) continue;
                var p = QuayPaths.Anchors[i];
                Arc(p, .45f, .50f, 0, Mathf.Tau, amber);
                var side = V2.Normalize(new V2(-(p - QuayPaths.Summit).Y, (p - QuayPaths.Summit).X)) * .033f;
                Quad(p + side, QuayPaths.Summit + side, QuayPaths.Summit - side, p - side, amber, .64f);
            }
        }
        if (Fight.Phase == QuayPhase.Homeward) Arc(ShoreFight.Dock, .45f, .50f, 0, Mathf.Tau, mint);
        traces.SurfaceEnd();
    }
    void Arc(V2 center, float inside, float outside, float start, float sweep, Color color, float lift = .03f)
    {
        if (outside <= inside) return;
        int count = Math.Max(5, (int)MathF.Ceiling(sweep * 8));
        for (int i = 0; i < count; i++)
        {
            float a = start + sweep * i / count, b = start + sweep * (i + 1) / count;
            V2 u = new(MathF.Cos(a), MathF.Sin(a)), v = new(MathF.Cos(b), MathF.Sin(b));
            Quad(center + u * inside, center + u * outside, center + v * outside, center + v * inside, color, lift);
        }
    }
    void Quad(V2 a, V2 b, V2 c, V2 d, Color color, float lift)
    {
        traces.SurfaceSetColor(color);
        traces.SurfaceAddVertex(Point(a, lift)); traces.SurfaceAddVertex(Point(b, lift)); traces.SurfaceAddVertex(Point(c, lift));
        traces.SurfaceAddVertex(Point(a, lift)); traces.SurfaceAddVertex(Point(c, lift)); traces.SurfaceAddVertex(Point(d, lift));
    }
}
