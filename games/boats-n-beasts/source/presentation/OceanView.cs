using Godot;
using BoatsNBeasts.Core;
using V2 = System.Numerics.Vector2;
namespace BoatsNBeasts;

public partial class OceanView : Node2D
{
    public Voyage Voyage = null!;
    public bool Menu, ReducedMotion;
    public Vector2 Camera;
    public float Clock, Shake;
    public double DrawMs;
    public V2? Destination;
    public static readonly Color Cream = new("ffe5af"), Coral = new("ff7651"), Aqua = new("63dccc"), Navy = new("0a2939");
    ProceduralArt art = null!;
    CreatureAtlas creatures = null!;
    SceneryCache scenery = null!;
    public int CachedScenery => scenery.Count;
    public ShaderMaterial Water = null!;
    readonly List<Particle> particles = new();
    readonly List<Wake> wakes = new();
    readonly RandomNumberGenerator rng = new();
    float wakeClock, muzzleTime;
    record Wake(Vector2 P, float Angle, float Born, float Speed);
    sealed class Particle { public Vector2 P, V, End; public float Life, MaxLife, Size; public string Kind = ""; public Color Color; }
    public override void _Ready() { art = new(this); creatures = new(); AddChild(creatures); scenery = new(); AddChild(scenery); rng.Seed = 77; }
    public static Vector2 G(V2 v) => new(v.X, v.Y);
    public Vector2 Screen(V2 p) => G(p) - Camera + GetViewportRect().Size * .5f;
    public void Reset() { scenery.Clear(); particles.Clear(); wakes.Clear(); Camera = G(Voyage.Position); }
    public void Advance(float dt)
    {
        if (Menu || Voyage.Mode == VoyageMode.Sailing) { Clock += dt; muzzleTime = Math.Max(0, muzzleTime-dt); }
        if (!Menu && Voyage.Mode == VoyageMode.Sailing)
        {
            Camera = Camera.Lerp(G(Voyage.Position) + (ReducedMotion ? Vector2.Zero : G(Voyage.Velocity) * .16f), 1 - Mathf.Exp(-dt * 5));
            wakeClock += dt;
            if (wakeClock > .045f && Voyage.Velocity.Length() > 20)
            { wakeClock = 0; wakes.Add(new(G(Voyage.Position), Voyage.Heading, Clock, Voyage.Velocity.Length())); }
        }
        if (Menu) Camera = new(-210, 15);
        if (Menu || Voyage.Mode == VoyageMode.Sailing)
        {
            foreach (var p in particles) { p.Life -= dt; p.P += p.V * dt; p.V *= MathF.Exp(-dt * 2); }
            particles.RemoveAll(p => p.Life <= 0); wakes.RemoveAll(w => Clock - w.Born > 2.1f); Shake = Math.Max(0, Shake - dt * 20);
        }
        if (Water != null) { Water.SetShaderParameter("ocean_time", Clock); Water.SetShaderParameter("camera", Camera); Water.SetShaderParameter("resolution", GetViewportRect().Size); }
        scenery.Sync(Voyage.World.Places, Camera, GetViewportRect().Size);
        if ((int)(Clock * 2) != (int)((Clock-dt)*2)) art.Trim(Voyage.World.Places.Select(p=>p.Style));
        QueueRedraw();
    }
    public void Effect(GameEvent e)
    {
        if (e.Kind == "boss") particles.Add(new() { P = G(e.Position), Life = 1.3f, MaxLife = 1.3f, Kind = "ring", Size = 1200, Color = Coral });
        if (e.Kind == "shot") muzzleTime = .08f;
        if (e.Kind == "hurt") Shake = ReducedMotion ? 0 : 6;
        if (e.Kind == "calm") { particles.Add(new() { P = G(e.Position), Life = 3, MaxLife = 3, Kind = "bulwark", Size = e.Value, Color = Aqua }); return; }
        if (e.Kind is "aura" or "bulwark" or "broadside") { particles.Add(new() { P = G(e.Position), End = G(e.End), Life = e.Kind == "broadside" ? .3f : .6f, MaxLife = e.Kind == "broadside" ? .3f : .6f, Kind = e.Kind, Size = e.Value, Color = e.Kind == "broadside" ? Cream : Aqua }); return; }
        if (e.Kind == "arc") { particles.Add(new() { P = G(e.Position), End = G(e.End), Life = .23f, MaxLife = .23f, Kind = "arc", Color = Aqua }); return; }
        if (e.Kind is "explosion" or "slam") particles.Add(new() { P = G(e.Position), Life = .5f, MaxLife = .5f, Kind = "ring", Size = e.Value > 0 ? e.Value : 130, Color = e.Kind == "slam" ? Coral : Cream });
        if (e.Kind is not ("hit" or "kill" or "explosion" or "hurt" or "boost" or "catch")) return;
        int count = e.Kind == "kill" ? 18 : e.Kind == "explosion" ? 24 : e.Kind == "hit" ? 5 : 3;
        for (int i = 0; i < count && particles.Count < 500; i++)
        {
            float a = rng.RandfRange(0, Mathf.Tau), speed = rng.RandfRange(20, 110), life = rng.RandfRange(.2f, .7f);
            particles.Add(new() { P = G(e.Position), V = Vector2.FromAngle(a) * speed, Life = life, MaxLife = life, Size = rng.RandfRange(2, 6), Color = e.Kind == "hurt" || e.Kind == "kill" ? Coral : Cream });
        }
    }
    public override void _Draw()
    {
        if (Voyage == null || art == null) return;
        var drawStart = System.Diagnostics.Stopwatch.GetTimestamp();
        var size = GetViewportRect().Size;

        // Broad tonal bands and sparse world-anchored turquoise glints preserve the spacious reference.

        int left = (int)MathF.Floor((Camera.X - size.X / 2) / 150) - 1, top = (int)MathF.Floor((Camera.Y - size.Y / 2) / 120) - 1;
        for (int y = top; y < top + 12; y++) for (int x = left; x < left + 14; x++)
        {
            uint h = SeedRandom.Hash(Voyage.World.Seed, x, y);
            if (h % 3 != 0) continue;
            Vector2 p = new Vector2(x * 150 + h % 100, y * 120 + (h >> 9) % 80) - Camera + size / 2;
            p.X += MathF.Sin(Clock * .5f + h % 23) * 7;
            float alpha = .12f + .06f * MathF.Sin(Clock * .5f + h % 17);
            DrawPolyline([p, p + new Vector2(9, -2), p + new Vector2(22, 0), p + new Vector2(30, -3)], new Color(Aqua, alpha), 2, true);
        }
        if (!Menu && Destination is V2 goal) { var at = Screen(goal); DrawArc(at, 17, Clock, Clock + Mathf.Tau * .8f, 30, new Color(Cream, .5f), 2, true); DrawCircle(at, 3, Cream); }
        foreach (var place in Voyage.World.Places)
        {
            Vector2 p = Screen(place.Position);
            float margin = place.Kind == PlaceKind.Fishing ? 100 : SceneryCache.Margin(place);
            if (p.X < -margin || p.X > size.X + margin || p.Y < -margin || p.Y > size.Y + margin) continue;
            if (place.Kind == PlaceKind.Fishing) { DrawFishing(place, p); continue; }
            if (place.Kind == PlaceKind.Harbor && !Menu)
            {
                for (int i=0;i<24;i++) { float a=i*Mathf.Tau/24; DrawArc(p,285,a,a+.12f,5,new Color(Aqua,.25f),2,true); }
            }
            float r = place.Radius;
            if (!scenery.Draw(this, place, p))
            {
                if (place.Kind == PlaceKind.Rock) art.Rocks(p, r, place.Style);
                else art.Island(p, place.Kind == PlaceKind.Harbor ? 156 : r * 1.15f, place.Style, place.Kind == PlaceKind.Harbor, Clock);
            }
            if (place.Kind == PlaceKind.Harbor && !Menu)
            {
                var badge = p + new Vector2(49, 201);
                DrawCircle(badge, 18, Cream); DrawLine(badge-new Vector2(0,9),badge+new Vector2(0,8),Navy,2.5f);
                DrawArc(badge+new Vector2(0,2),8,0,Mathf.Pi,18,Navy,2.5f,true);DrawCircle(badge-new Vector2(0,10),3,Navy,false,2,true);
            }
        }
        if (wakes.Count > 1)
        {
            var leftWake = new Vector2[wakes.Count]; var rightWake = new Vector2[wakes.Count]; var colors = new Color[wakes.Count];
            for (int i = 0; i < wakes.Count; i++)
            {
                var w = wakes[i]; float age = Clock - w.Born;
                Vector2 back = Vector2.FromAngle(w.Angle + Mathf.Pi / 2), side = back.Orthogonal();
                var stern = w.P - Camera + size / 2 + back * 49;
                float spread = 13 + age * 17;
                leftWake[i] = stern - side * spread; rightWake[i] = stern + side * spread;
                colors[i] = new Color(Aqua, (1 - age / 2.1f) * .48f);
            }
            DrawPolylineColors(leftWake, colors, 3, true); DrawPolylineColors(rightWake, colors, 3, true);
        }
        if (!Menu && Voyage.Weapons[4] > 0)
        {
            var at = Screen(Voyage.Position); float r = (130 + Voyage.Weapons[4] * 8) * Voyage.Area;
            DrawCircle(at, r, new Color(Aqua, .045f));
            for (int i = 0; i < 5; i++) { float a = Clock * .7f + i * Mathf.Tau / 5; DrawArc(at, r, a, a + .58f, 14, new Color(Aqua, .25f), 2, true); }
        }
        foreach (var e in Voyage.Enemies.OrderBy(e => e.Position.Y))
        {
            Vector2 p = Screen(e.Position);
            float margin = e.Kind == EnemyKind.Leviathan ? 180 : 100;
            if (p.X < -margin || p.Y < -margin || p.X > size.X + margin || p.Y > size.Y + margin) continue;
            float h = e.Kind == EnemyKind.Leviathan ? 230 : e.Kind == EnemyKind.Serpent ? 119 : e.Kind == EnemyKind.Ray ? 115 : 95;
            if (e.Telegraph > 0)
            {
                DrawArc(p, e.Radius + 13 + MathF.Sin(Clock * 16) * 3, 0, Mathf.Tau, 40, new Color(Coral, .8f), 3, true);
                if (e.Kind == EnemyKind.Serpent) DrawLine(p, p + G(e.Direction) * 230, new Color(Coral, .35f), 15, true);
            }
            float angle = MathF.Atan2(Voyage.Position.Y - e.Position.Y, Voyage.Position.X - e.Position.X);
            DrawEllipse(p + new Vector2(0, 13), new(e.Radius * 1.3f, e.Radius * .48f), new Color(Aqua, .07f));
            creatures.Draw(this, e, p + new Vector2(0, MathF.Sin(e.Time * 4) * 2), angle);
            if (e.Mark > 0) DrawArc(p, e.Radius + 5, 0, Mathf.Tau, 28, Aqua, 2, true);
            if (e.Health < e.MaxHealth && e.Kind != EnemyKind.Leviathan)
            { DrawLine(p + new Vector2(-23, -h * .52f), p + new Vector2(23, -h * .52f), Navy, 4); DrawLine(p + new Vector2(-23, -h * .52f), p + new Vector2(-23 + 46 * Math.Max(0, e.Health / e.MaxHealth), -h * .52f), Coral, 3); }
        }
        foreach (var s in Voyage.Shots)
        {
            Vector2 p = Screen(s.Position);
            if (p.X < -40 || p.Y < -40 || p.X > size.X + 40 || p.Y > size.Y + 40) continue;
            Vector2 dir = G(OceanWorld.Unit(s.Velocity));
            if (s.Hostile) { DrawCircle(p, 11, Navy); DrawCircle(p, 8, Coral); DrawCircle(p - new Vector2(2, 2), 2, Cream); }
            else if (s.Kind == WeaponKind.Mortar) { DrawCircle(p, 12, new Color(Navy, .45f)); DrawCircle(p - new Vector2(0, 25 * MathF.Sin(MathF.Min(s.Life, 1) * Mathf.Pi)), 7, Cream); }
            else { DrawLine(p - dir * (s.Kind == WeaponKind.Harpoon ? 26 : 16), p, s.Kind == WeaponKind.Harpoon ? Aqua : Cream, 5, true); DrawLine(p - dir * 8, p + dir * 3, Cream, 3, true); }
        }
        var boatPos = Menu ? new Vector2(size.X * .73f, size.Y * .57f) : Screen(Voyage.Position);
        if (Shake > 0) boatPos += new Vector2(MathF.Sin(Clock * 100), MathF.Cos(Clock * 90)) * Shake;

        float heading = Menu ? -.65f : Voyage.Heading;
        var target = Voyage.Enemies.Where(e=>e.Health>0 && System.Numerics.Vector2.DistanceSquared(e.Position,Voyage.Position)<570*570).OrderBy(e=>System.Numerics.Vector2.DistanceSquared(e.Position,Voyage.Position)).FirstOrDefault();
        var mount = Voyage.Position + new V2(MathF.Sin(heading), -MathF.Cos(heading)) * (48 * (Voyage.Boat == BoatKind.Cutter ? 139f / 145 : 151f / 145));
        float aim = target == null ? 0 : MathF.Atan2(target.Position.Y-mount.Y,target.Position.X-mount.X)+Mathf.Pi/2-heading;
        art.Boat(boatPos + new Vector2(0, ReducedMotion ? 0 : MathF.Sin(Clock * 2.7f) * 1.4f), Menu ? 235 : Voyage.Boat == BoatKind.Cutter ? 139 : 151, heading, Voyage.Boat, Clock, Voyage.Weapons, Voyage.Invulnerable > 0 && (int)(Clock * 16) % 2 == 0, aim, muzzleTime > 0);
        if (Menu)
        {
            art.Monster(new(size.X * .84f, size.Y * .26f), 150, EnemyKind.Crab, Clock);
            art.Monster(new(size.X * .85f, size.Y * .81f), 225, EnemyKind.Serpent, Clock);
        }
        foreach (var p in particles)
        {
            Vector2 at = p.P - Camera + size / 2; float alpha = p.Life / p.MaxLife;
            if (p.Kind is "aura" or "bulwark") { float r = Math.Max(1, p.Size * (1 - alpha * .75f)); DrawArc(at, r, 0, Mathf.Tau, 60, new Color(Aqua, alpha * .65f), p.Kind == "bulwark" ? 7 : 2, true); }
            else if (p.Kind == "broadside")
            {
                float angle = (p.End - p.P).Angle();
                for (int i = -5; i <= 5; i++) { var d = Vector2.FromAngle(angle + i * Voyage.BroadsideHalfAngle / 5); DrawLine(at + d * p.Size * (1-alpha) * .6f, at + d * p.Size * (1-alpha*.5f), new Color(Cream, alpha), 3, true); }
                DrawArc(at, p.Size * (1-alpha*.5f), angle-Voyage.BroadsideHalfAngle, angle+Voyage.BroadsideHalfAngle, 24, new Color(Cream, alpha*.4f), 2, true);
            }
            else if (p.Kind == "arc") { Vector2 end = p.End - Camera + size / 2; DrawPolyline([at, at.Lerp(end, .3f) + new Vector2(0, 15), at.Lerp(end, .6f) - new Vector2(0, 12), end], new Color(Aqua, alpha), 4, true); }
            else if (p.Kind == "ring") DrawArc(at, Math.Max(1, p.Size * (1 - alpha)), 0, Mathf.Tau, 40, new Color(p.Color, alpha), 4, true);
            else DrawCircle(at, p.Size * alpha, new Color(p.Color, alpha));
        }
        DrawMs = DrawMs * .95 + System.Diagnostics.Stopwatch.GetElapsedTime(drawStart).TotalMilliseconds * .05;
    }
    void DrawFishing(Place place, Vector2 p)
    {
        bool casting = Voyage.Mode == VoyageMode.Fishing && Voyage.FishingPlace?.Id == place.Id;
        if (Voyage.World.FishLeft(place) == 0 && !casting) return;
        float pulse = (Clock * .45f) % 1;
        DrawEllipse(p, new(48, 29), new Color(Aqua, .12f));
        EllipseArc(p, new(46, 26), new Color(Aqua, .75f), 3);
        EllipseArc(p + new Vector2(2,-1), new(38, 21), new Color(Aqua, .32f), 2);
        EllipseArc(p, new(46 + pulse * 20, 26 + pulse * 12), new Color(Aqua, .45f * (1 - pulse)), 2);
        for (int i = 0; i < 3; i++)
        {
            float a = i * Mathf.Tau / 3 + Clock * .35f;
            Vector2 fish = p + new Vector2(MathF.Cos(a) * 23, MathF.Sin(a) * 12);
            DrawEllipse(fish, new(7, 3), Cream);
            DrawColoredPolygon([fish + new Vector2(-4, 0), fish + new Vector2(-9, -3), fish + new Vector2(-9, 3)], Cream);
        }
    }
    void DrawEllipse(Vector2 p, Vector2 radius, Color color) { DrawSetTransform(p, 0, radius); DrawCircle(Vector2.Zero, 1, color); DrawSetTransform(Vector2.Zero); }
    void EllipseArc(Vector2 p, Vector2 radius, Color color, float width)
    {
        var points = new Vector2[49]; for (int i = 0; i < points.Length; i++) { float a = i / 48f * Mathf.Tau; points[i] = p + new Vector2(Mathf.Cos(a) * radius.X, Mathf.Sin(a) * radius.Y); } DrawPolyline(points, color, width, true);
    }
}
