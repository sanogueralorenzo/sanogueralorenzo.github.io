using Godot;
using WizNDragons.Core;
using V2 = System.Numerics.Vector2;
namespace WizNDragons;

// Read-only flight presentation; owns bounded native scene resources.
public partial class SkyView3D : Node3D
{
    public Flight Flight = null!;
    public bool Menu;
    public Vector2 Camera;
    public float Clock;
    public float DepartureTime { get; private set; }
    public double DrawMs;
    public V2? Destination;
    public Vector2 Projection => new(NativeStage3D.Zoom, NativeStage3D.Zoom * NativeStage3D.Foreshortening);
    public int CachedScenery => clouds.Count;
    public int CachedEncounters => effects.CachedEncounters;
    public int TrailSamples => effects.TrailSamples;
    CloudLayers3D clouds = null!;
    readonly Dictionary<int, Node3D> creatures = new();
    NativeStage3D stage = null!;
    Effects3D effects = null!;
    Node3D? wizard;
    string wizardSignature = "";
    public override void _Ready()
    {
        stage = new(); AddChild(stage);
        clouds = new(); AddChild(clouds);
        effects = new(); AddChild(effects);
        Reset();
    }
    public Vector2 Screen(V2 p) => stage.Screen(p);
    public Vector2 ElevatedScreen(V2 p, float height) => stage.Screen(p, height);
    public V2 WorldPoint(Vector2 screen) => stage.WorldPoint(screen);
    public void Reset()
    {
        clouds.Reset();
        foreach (var root in creatures.Values) root.QueueFree(); creatures.Clear();
        wizard?.QueueFree(); wizard = null; wizardSignature = "";
        ActorArt3D.ResetCache();
        effects.Reset(); Clock = 0; DepartureTime = 0; Camera = HomeCamera();
        stage.Follow(Camera);
    }
    Vector2 HomeCamera() => Vector2.Zero;
    public void BeginFlying() { Menu = false; DepartureTime = 0; }
    public void Effect(GameEvent ev) => effects.Effect(ev);
    public void Advance(float dt)
    {
        var start = System.Diagnostics.Stopwatch.GetTimestamp();
        if (Menu || Flight.IsActive) Clock += dt;
        if (Menu) Camera = HomeCamera();
        else if (Flight.Mode == FlightMode.Flying && (Flight.Velocity.LengthSquared() > .01f || DepartureTime > 0))
        {
            DepartureTime += dt;
            var target = new Vector2(Flight.Position.X + Flight.Velocity.X * .16f, Flight.Position.Y + Flight.Velocity.Y * .16f);
            // Ease from the title framing into camera-follow flight.
            float follow = Mathf.SmoothStep(0, 1, Mathf.Clamp((DepartureTime - .8f) / 2, 0, 1));
            Camera = Camera.Lerp(target, 1 - Mathf.Exp(-dt * 5 * follow));
        }
        stage.Follow(Camera); stage.Advance(Clock);
        SyncScenery(); SyncActors();
        effects.Destination = Destination;
        effects.Sync(Flight, Clock, dt);
        DrawMs = DrawMs * .95 + System.Diagnostics.Stopwatch.GetElapsedTime(start).TotalMilliseconds * .05;
    }
    void SyncScenery() => clouds.Sync(Camera, Clock, Flight.World.Seed);
    void SyncActors()
    {
        string signature = Flight.Wizard + ":" + string.Join(',', Flight.Spells);
        if (signature != wizardSignature)
        {
            wizard?.QueueFree(); wizard = ActorArt3D.Wizard(Flight.Wizard, Flight.Spells); AddChild(wizard); wizardSignature = signature;
        }
        wizard!.Position = NativeStage3D.Point(Flight.Position);
        wizard.Rotation = new(0, -Flight.Heading, 0);
        var target = Flight.Enemies.Where(e => e.Health > 0 && V2.DistanceSquared(e.Position, Flight.Position) < 570 * 570).OrderBy(e => V2.DistanceSquared(e.Position, Flight.Position)).FirstOrDefault();
        var aim = target == null ? 0 : Flight.Heading - MathF.Atan2(target.Position.X - Flight.Position.X, Flight.Position.Y - target.Position.Y);
        ActorArt3D.AnimateWizard(wizard, Clock, Flight.Velocity.Length() * .01f, aim);
        var live = Flight.Enemies.Select(e => e.Id).ToHashSet();
        foreach (var id in creatures.Keys.Where(id => !live.Contains(id)).ToArray()) { creatures[id].QueueFree(); creatures.Remove(id); }
        foreach (var enemy in Flight.Enemies)
        {
            if (!creatures.TryGetValue(enemy.Id, out var root))
            {
                root = ActorArt3D.Creature(enemy.Kind); AddChild(root); creatures.Add(enemy.Id, root);
                var mesh = root.GetChild<MeshInstance3D>(0);
                mesh.SetInstanceShaderParameter("creature_kind", enemy.Kind switch { EnemyKind.Imp or EnemyKind.ElderDragon => 1, EnemyKind.Spark => 2, EnemyKind.Drake => 3, _ => 4 });
                mesh.SetInstanceShaderParameter("creature_scale", enemy.Kind == EnemyKind.ElderDragon ? 2.65f : 1);
                mesh.SetInstanceShaderParameter("phase", enemy.Id * .73f);
                mesh.SetInstanceShaderParameter("movement_rate", enemy.SpeedMultiplier);
            }
            float swelling = enemy.Fuse > 0 ? 1 - enemy.Fuse / Enemy.SparkFuseDuration : 0;
            root.Scale = Vector3.One * (1 + swelling * .55f);
            root.GetChild<MeshInstance3D>(0).SetInstanceShaderParameter("swelling", swelling);
            float emergence = Mathf.Clamp(enemy.Time / Enemy.EmergenceDuration, 0, 1);
            root.Position = NativeStage3D.Point(enemy.Position, -(1 - emergence) * (enemy.Kind == EnemyKind.ElderDragon ? 1.2f : .6f));
            var toward = Flight.Position - enemy.Position;
            root.Rotation = new(0, -MathF.Atan2(toward.X, -toward.Y), 0);
            ActorArt3D.Animate(root, Clock + enemy.Id * .73f, enemy.Dash > 0 ? 3 : 1);
        }
    }
}
