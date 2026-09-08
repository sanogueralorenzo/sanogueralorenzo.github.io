using Godot;
using BoatsNBeasts.Core;
using V2 = System.Numerics.Vector2;
namespace BoatsNBeasts;

// Read-only presentation of the existing voyage. Owns only bounded native scene resources.
public partial class OceanView3D : Node3D
{
    public Voyage Voyage = null!;
    public bool Menu;
    public Vector2 Camera;
    public float Clock;
    public double DrawMs;
    public V2? Destination;
    public Vector2 Projection => new(NativeStage3D.Zoom, NativeStage3D.Zoom * NativeStage3D.Foreshortening);
    public int CachedScenery => scenery.Count;
    public int CachedEncounters => effects.CachedEncounters;
    public int TrailSamples => effects.TrailSamples;
    readonly Dictionary<string, Node3D> scenery = new();
    readonly Dictionary<int, Node3D> creatures = new();
    NativeStage3D stage = null!;
    Effects3D effects = null!;
    Node3D? boat;
    string boatSignature = "";
    public override void _Ready()
    {
        stage = new(); AddChild(stage);
        effects = new(); AddChild(effects);
        Reset();
    }
    public Vector2 Screen(V2 p) => stage.Screen(p);
    public Vector2 ElevatedScreen(V2 p, float height) => stage.Screen(p, height);
    public V2 WorldPoint(Vector2 screen) => stage.WorldPoint(screen);
    public void Reset()
    {
        foreach (var root in scenery.Values) root.QueueFree(); scenery.Clear();
        foreach (var root in creatures.Values) root.QueueFree(); creatures.Clear();
        boat?.QueueFree(); boat = null; boatSignature = "";
        effects.Reset(); Clock = 0; Camera = new(Voyage.Position.X, Voyage.Position.Y);
        stage.Follow(Camera);
    }
    public void Effect(GameEvent ev) => effects.Effect(ev);
    public void Advance(float dt)
    {
        var start = System.Diagnostics.Stopwatch.GetTimestamp();
        if (Menu || Voyage.Mode == VoyageMode.Sailing) Clock += dt;
        if (Menu) Camera = new(-210, 15);
        else if (Voyage.Mode == VoyageMode.Sailing)
        {
            var target = new Vector2(Voyage.Position.X + Voyage.Velocity.X * .16f, Voyage.Position.Y + Voyage.Velocity.Y * .16f);
            Camera = Camera.Lerp(target, 1 - Mathf.Exp(-dt * 5));
        }
        stage.Follow(Camera); stage.Advance(Clock);
        SyncScenery(); SyncActors();
        effects.Destination = Destination; effects.Sync(Voyage, Clock, dt);
        DrawMs = DrawMs * .95 + System.Diagnostics.Stopwatch.GetElapsedTime(start).TotalMilliseconds * .05;
    }
    void SyncScenery()
    {
        var size = GetViewport().GetVisibleRect().Size / Projection;
        var visible = Voyage.World.Places.Where(p => OceanWorld.IsSolid(p) &&
            Math.Abs(p.Position.X - Camera.X) < size.X * .5f + p.Radius + 400 &&
            Math.Abs(p.Position.Y - Camera.Y) < size.Y * .5f + p.Radius + 500).ToArray();
        var keep = visible.Select(p => p.Id).ToHashSet();
        foreach (var id in scenery.Keys.Where(id => !keep.Contains(id)).ToArray()) { scenery[id].QueueFree(); scenery.Remove(id); }
        // Build at most one incoming island per frame, ahead of the visible edge during sailing.
        var incoming = visible.Where(p => !scenery.ContainsKey(p.Id)).OrderBy(p => V2.DistanceSquared(p.Position, new(Camera.X, Camera.Y))).FirstOrDefault();
        if (incoming != null)
        {
            var root = EnvironmentArt3D.Build(incoming); AddChild(root);
            root.Position = NativeStage3D.Point(incoming.Position); scenery.Add(incoming.Id, root);
        }
    }
    void SyncActors()
    {
        string signature = Voyage.Boat + ":" + string.Join(',', Voyage.Weapons);
        if (signature != boatSignature)
        {
            boat?.QueueFree(); boat = ActorArt3D.Boat(Voyage.Boat, Voyage.Weapons); AddChild(boat); boatSignature = signature;
        }
        boat!.Position = NativeStage3D.Point(Voyage.Position);
        boat.Rotation = new(0, -Voyage.Heading, 0);
        var target = Voyage.Enemies.Where(e => e.Health > 0 && V2.DistanceSquared(e.Position, Voyage.Position) < 570 * 570).OrderBy(e => V2.DistanceSquared(e.Position, Voyage.Position)).FirstOrDefault();
        var aim = target == null ? 0 : Voyage.Heading - MathF.Atan2(target.Position.X - Voyage.Position.X, Voyage.Position.Y - target.Position.Y);
        ActorArt3D.AnimateBoat(boat, Clock, Voyage.Velocity.Length() * .01f, aim);
        var live = Voyage.Enemies.Select(e => e.Id).ToHashSet();
        foreach (var id in creatures.Keys.Where(id => !live.Contains(id)).ToArray()) { creatures[id].QueueFree(); creatures.Remove(id); }
        foreach (var enemy in Voyage.Enemies)
        {
            if (!creatures.TryGetValue(enemy.Id, out var root))
            {
                root = ActorArt3D.Creature(enemy.Kind); AddChild(root); creatures.Add(enemy.Id, root);
                var mesh = root.GetChild<MeshInstance3D>(0);
                mesh.SetInstanceShaderParameter("creature_kind", enemy.Kind switch { EnemyKind.Crab or EnemyKind.Leviathan => 1, EnemyKind.Puffer => 2, EnemyKind.Serpent => 3, _ => 4 });
                mesh.SetInstanceShaderParameter("creature_scale", enemy.Kind == EnemyKind.Leviathan ? 2.65f : 1);
                mesh.SetInstanceShaderParameter("phase", enemy.Id * .73f);
            }
            float emergence = Mathf.Clamp(enemy.Time / Enemy.EmergenceDuration, 0, 1);
            root.Position = NativeStage3D.Point(enemy.Position, -(1 - emergence) * (enemy.Kind == EnemyKind.Leviathan ? 1.2f : .6f));
            var toward = Voyage.Position - enemy.Position;
            root.Rotation = new(0, -MathF.Atan2(toward.X, -toward.Y), 0);
            ActorArt3D.Animate(root, Clock + enemy.Id * .73f, enemy.Dash > 0 ? 3 : 1);
        }
    }
}
