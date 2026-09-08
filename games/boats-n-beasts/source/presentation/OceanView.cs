using Godot;
using BoatsNBeasts.Core;
using V2 = System.Numerics.Vector2;
namespace BoatsNBeasts;

public partial class OceanView : Node2D
{
    public Voyage Voyage = null!;
    public bool Menu;
    public Vector2 Camera;
    public float Clock, Shake;
    public double DrawMs;
    public V2? Destination;
    public static readonly Color Cream = new("ffe5af"), Coral = new("ff7651"), Aqua = new("63dccc"), Navy = new("0a2939");
    ProceduralArt art = null!;
    SeaEncounters encounters = null!;
    CreatureAtlas creatures = null!;
    SceneryCache scenery = null!;
    public int CachedScenery => scenery.Count;
    public ShaderMaterial Water = null!;
    readonly List<Particle> particles = new();
    readonly List<Wake> wakes = new();
    readonly Dictionary<Shot,List<Vector2>> orbTrails = new();
    readonly Dictionary<int,List<Vector2>> creatureWakes = new();
    float trailClock;
    readonly RandomNumberGenerator rng = new();
    float wakeClock, muzzleTime;
    record Wake(Vector2 P, float Angle, float Born, float Speed);
    sealed class Particle { public Vector2 P, V, End; public float Life, MaxLife, Size; public string Kind = ""; public Color Color; }
    public override void _Ready() { art = new(this); encounters = new(this); creatures = new(); AddChild(creatures); scenery = new(); AddChild(scenery); rng.Seed = 77; }
    public static Vector2 G(V2 v) => new(v.X, v.Y);
    public const float CameraZoom = .74f, GroundForeshortening = .84f;
    public Vector2 Projection => Menu ? Vector2.One : new(CameraZoom, CameraZoom * GroundForeshortening);
    Vector2 ViewSize => GetViewportRect().Size / Projection;
    Vector2 CanvasPoint(V2 p) => G(p) - Camera + ViewSize * .5f;
    public Vector2 Screen(V2 p) => CanvasPoint(p) * Projection;
    public V2 WorldPoint(Vector2 screen) { var p = (screen - GetViewportRect().Size * .5f) / Projection + Camera; return new(p.X, p.Y); }
    public void Reset() { scenery.Clear(); particles.Clear(); wakes.Clear(); orbTrails.Clear(); creatureWakes.Clear(); trailClock=0; Camera = G(Voyage.Position); }
    public void Advance(float dt)
    {
        Scale = Projection;
        if (Menu || Voyage.Mode == VoyageMode.Sailing) { Clock += dt; muzzleTime = Math.Max(0, muzzleTime-dt); }
        if (!Menu && Voyage.Mode == VoyageMode.Sailing)
        {
            Camera = Camera.Lerp(G(Voyage.Position) + (G(Voyage.Velocity) * .16f), 1 - Mathf.Exp(-dt * 5));
            trailClock += dt;
            if (trailClock >= .065f)
            {
                trailClock = 0;
                var liveOrbs=Voyage.Shots.Where(s=>s.Kind==WeaponKind.Arcane && !s.Hostile && s.Life>0).ToHashSet();
                foreach(var old in orbTrails.Keys.Where(s=>!liveOrbs.Contains(s)).ToArray()) orbTrails.Remove(old);
                foreach(var shot in liveOrbs)
                {
                    if(!orbTrails.TryGetValue(shot,out var trail)) orbTrails[shot]=trail=new();
                    trail.Add(G(shot.Position)); if(trail.Count>9) trail.RemoveAt(0);
                }
                var liveIds=Voyage.Enemies.Select(e=>e.Id).ToHashSet();
                foreach(var old in creatureWakes.Keys.Where(id=>!liveIds.Contains(id)).ToArray()) creatureWakes.Remove(old);
                foreach(var enemy in Voyage.Enemies)
                {
                    if(!creatureWakes.TryGetValue(enemy.Id,out var trail)) creatureWakes[enemy.Id]=trail=new();
                    trail.Add(G(enemy.Position)); if(trail.Count>13) trail.RemoveAt(0);
                }
            }
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
        if (Water != null) { Water.SetShaderParameter("ocean_time", Clock); Water.SetShaderParameter("camera", Camera); Water.SetShaderParameter("resolution", GetViewportRect().Size); Water.SetShaderParameter("projection", Projection); }
        scenery.Sync(Voyage.World.Places, Camera, ViewSize);
        if ((int)(Clock * 2) != (int)((Clock-dt)*2)) art.Trim(Voyage.World.Places.Select(p=>p.Style));
        QueueRedraw();
    }
    public void Effect(GameEvent e)
    {
        if (e.Kind == "level") particles.Add(new() { P=G(e.Position), Life=.5f, MaxLife=.5f, Kind="ring", Size=100, Color=Aqua });
        if (e.Kind == "boss") particles.Add(new() { P = G(e.Position), Life = 1.3f, MaxLife = 1.3f, Kind = "ring", Size = 1200, Color = Coral });
        if (e.Kind is "boostStart" or "treasure" or "salvage") particles.Add(new() { P=G(e.Position), Life=.4f, MaxLife=.4f, Kind="ring", Size=e.Kind=="boostStart"?65:85, Color=e.Kind=="boostStart"?Aqua:Cream });
        if (e.Kind == "pull") { particles.Add(new() { P=G(e.Position), End=G(e.End), Life=.18f, MaxLife=.18f, Kind="pull", Size=e.Value, Color=Cream }); return; }
        if (e.Kind == "ricochet") { particles.Add(new() { P=G(e.Position), Life=.16f, MaxLife=.16f, Kind="ring", Size=20, Color=Cream }); return; }
        if (e.Kind == "shot") muzzleTime = .08f;
        if (e.Kind == "hurt") Shake = 6;
        if (e.Kind == "calm") { particles.Add(new() { P = G(e.Position), Life = 3, MaxLife = 3, Kind = "bulwark", Size = e.Value, Color = Aqua }); return; }
        if (e.Kind is "aura" or "bulwark") { particles.Add(new() { P = G(e.Position), End = G(e.End), Life = .4f, MaxLife = .4f, Kind = e.Kind, Size = e.Value, Color = Aqua }); return; }
        if (e.Kind == "arc") { particles.Add(new() { P = G(e.Position), End = G(e.End), Life = .16f, MaxLife = .16f, Kind = "arc", Color = Aqua }); return; }
        if (e.Kind is "explosion" or "slam") particles.Add(new() { P = G(e.Position), Life = .5f, MaxLife = .5f, Kind = "ring", Size = e.Value > 0 ? e.Value : 130, Color = e.Kind == "slam" ? Coral : Cream });
        if (e.Kind is not ("hit" or "kill" or "explosion" or "hurt" or "boost" or "catch")) return;
        int count = e.Kind == "kill" ? 7 : e.Kind == "explosion" ? 10 : e.Kind == "hit" ? 2 : 3;
        for (int i = 0; i < count && particles.Count < 500; i++)
        {
            float a = rng.RandfRange(0, Mathf.Tau), speed = rng.RandfRange(20, 110), life = rng.RandfRange(.12f, .32f);
            particles.Add(new() { P = G(e.Position), V = Vector2.FromAngle(a) * speed, Life = life, MaxLife = life, Size = rng.RandfRange(2, 6), Color = e.Kind == "hurt" ? Coral : Cream });
        }
    }
    public override void _Draw()
    {
        if (Voyage == null || art == null) return;
        var drawStart = System.Diagnostics.Stopwatch.GetTimestamp();
        var size = ViewSize;

        // Broad tonal bands and sparse world-anchored turquoise glints preserve the spacious reference.

        int left = (int)MathF.Floor((Camera.X - size.X / 2) / 150) - 1, top = (int)MathF.Floor((Camera.Y - size.Y / 2) / 120) - 1;
        for (int y = top; y < top + (int)(size.Y / 120) + 3; y++) for (int x = left; x < left + (int)(size.X / 150) + 3; x++)
        {
            uint h = SeedRandom.Hash(Voyage.World.Seed, x, y);
            if (h % 3 != 0) continue;
            Vector2 p = new Vector2(x * 150 + h % 100, y * 120 + (h >> 9) % 80) - Camera + size / 2;
            p.X += MathF.Sin(Clock * .5f + h % 23) * 7;
            float alpha = .12f + .06f * MathF.Sin(Clock * .5f + h % 17);
            DrawPolyline([p, p + new Vector2(9, -2), p + new Vector2(22, 0), p + new Vector2(30, -3)], new Color(Aqua, alpha), 1.5f, true);
            if(h%13==0)
            {
                float glint=Mathf.Pow(Mathf.Max(0,Mathf.Sin(Clock*.7f+h%29)),8)*.6f;
                DrawLine(p-new Vector2(5,0),p+new Vector2(8,-1),new Color(Cream,glint),1.5f,true);
            }
        }
        if (!Menu && Destination is V2 goal) { var at = CanvasPoint(goal); DrawArc(at, 17, Clock, Clock + Mathf.Tau * .8f, 30, new Color(Cream, .5f), 2, true); DrawCircle(at, 3, Cream); }
        foreach (var place in Voyage.World.Places)
        {
            Vector2 p = CanvasPoint(place.Position);
            float margin = place.Kind == PlaceKind.Fishing ? 100 : OceanWorld.IsSolid(place) ? SceneryCache.Margin(place) : place.Radius + 50;
            if (p.X < -margin || p.X > size.X + margin || p.Y < -margin || p.Y > size.Y + margin) continue;
            if (place.Kind == PlaceKind.Fishing) { DrawFishing(place, p); continue; }
            if (!OceanWorld.IsSolid(place)) { encounters.Draw(place,p,Clock,Voyage.World.Depletion.ContainsKey(place.Id)); continue; }
            if (place.Kind == PlaceKind.Harbor && !Menu)
            {
                for (int i=0;i<24;i++) { float a=i*Mathf.Tau/24; DrawArc(p,285,a,a+.12f,5,new Color(Aqua,.25f),2,true); }
            }
            float r = place.Radius;
            if (!scenery.IsReady(place))
            {
                if (place.Kind == PlaceKind.Rock) art.Rocks(p, r, place.Style);
                else art.Island(p, place.Kind == PlaceKind.Harbor ? 156 : r * 1.15f, place.Style, place.Kind == PlaceKind.Harbor, Clock);
            }
            if (place.Kind != PlaceKind.Rock) art.Surf(p, place.Kind == PlaceKind.Harbor ? 156 : r*1.15f, place.Style, Clock);
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
                float speedRatio=Mathf.Clamp(w.Speed/Voyage.Speed,.2f,2.6f);
                float spread = 13 + age * (12 + speedRatio * 7);
                leftWake[i] = stern - side * spread; rightWake[i] = stern + side * spread;
                colors[i] = new Color(new Color("b8e9da"), (1 - age / 2.1f) * Mathf.Clamp(speedRatio*.55f,.2f,.9f));
            }
            var haze=colors.Select(c=>new Color(c,c.A*.13f)).ToArray();
            DrawPolylineColors(leftWake,haze,12,true); DrawPolylineColors(rightWake,haze,12,true);
            DrawPolylineColors(leftWake,colors,Voyage.IsBoosting?4:2,true); DrawPolylineColors(rightWake,colors,Voyage.IsBoosting?4:2,true);
            for(int i=1;i<wakes.Count;i+=2)
            {
                float age=Clock-wakes[i].Born;
                var offset=Vector2.FromAngle(i*2.4f)*Mathf.Min(age*6,8);
                var foam=new Color(Cream,colors[i].A*.85f);
                DrawLine(leftWake[i]+offset,leftWake[i]+offset+new Vector2(3,1),foam,2.2f,true);
                DrawLine(rightWake[i]-offset,rightWake[i]-offset+new Vector2(3,-1),foam,2.2f,true);
            }
        }
        if (!Menu && Voyage.Weapons[4] > 0)
        {
            var at = CanvasPoint(Voyage.Position); float r = Voyage.WhirlpoolRadius;
            DrawCircle(at, r, new Color(Aqua, .045f));
            for (int i = 0; i < 5; i++) { float a = Clock * .7f + i * Mathf.Tau / 5; DrawArc(at, r, a, a + .58f, 14, new Color(Aqua, .25f), 2, true); }
        }
        foreach (var e in Voyage.Enemies.OrderBy(e => e.Position.Y))
        {
            Vector2 p = CanvasPoint(e.Position);
            float margin = e.Kind == EnemyKind.Leviathan ? 180 : 100;
            if (p.X < -margin || p.Y < -margin || p.X > size.X + margin || p.Y > size.Y + margin) continue;
            if(creatureWakes.TryGetValue(e.Id,out var history) && history.Count>2)
            {
                var away=history[0]-history[^1];
                if(away.LengthSquared()>100)
                {
                    var rear=away.Normalized(); var side=rear.Orthogonal();
                    for(int i=1;i<history.Count;i+=2)
                    {
                        float age=1-i/(float)history.Count;
                        var wake=history[i]-Camera+size/2+rear*e.Radius*.8f;
                        float spread=e.Radius*(.8f+age*.4f);
                        var color=new Color(Cream,(1-age)*.27f);
                        DrawLine(wake+side*spread,wake+side*spread+rear*6,color,1.8f,true);
                        DrawLine(wake-side*spread,wake-side*spread+rear*6,color,1.8f,true);
                    }
                }
            }
            float h = e.Kind == EnemyKind.Leviathan ? 230 : e.Kind == EnemyKind.Serpent ? 119 : e.Kind == EnemyKind.Ray ? 115 : 95;
            if (e.Telegraph > 0)
            {
                DrawArc(p, e.Radius + 13 + MathF.Sin(Clock * 16) * 3, 0, Mathf.Tau, 40, new Color(Coral, .8f), 3, true);
                if (e.Kind == EnemyKind.Serpent) DrawLine(p, p + G(e.Direction) * 230, new Color(Coral, .35f), 15, true);
            }
            if (e.Emerging)
            {
                float progress = e.Time / Enemy.EmergenceDuration;
                DrawArc(p, e.Radius * (1 + progress), 0, Mathf.Tau, 32, new Color(Aqua, 1 - progress), 2, true);
            }
            float angle = MathF.Atan2(Voyage.Position.Y - e.Position.Y, Voyage.Position.X - e.Position.X);
            DrawEllipse(p + new Vector2(0, 13), new(e.Radius * 1.3f, e.Radius * .48f), new Color(Aqua, .07f));
            DrawEllipse(p+new Vector2(5,17),new(e.Radius*.95f,e.Radius*.43f),new Color(Navy,.32f));
            if (!e.Emerging)
            {
                float ripple=e.Time*.8f+e.Id;
                DrawArc(p+new Vector2(0,9),e.Radius*1.28f,ripple,ripple+1.7f,18,new Color(Cream,.2f),1.5f,true);
                DrawArc(p+new Vector2(0,9),e.Radius*1.4f,ripple+Mathf.Pi,ripple+Mathf.Pi+1.2f,14,new Color(Aqua,.25f),2,true);
            }
            creatures.Draw(this, e, p + new Vector2(0, MathF.Sin(e.Time * 4) * 2), angle);
            if (e.Health < e.MaxHealth && e.Kind != EnemyKind.Leviathan)
            { DrawLine(p + new Vector2(-23, -h * .52f), p + new Vector2(23, -h * .52f), Navy, 4); DrawLine(p + new Vector2(-23, -h * .52f), p + new Vector2(-23 + 46 * Math.Max(0, e.Health / e.MaxHealth), -h * .52f), Coral, 3); }
        }
        foreach (var s in Voyage.Shots)
        {
            Vector2 p = CanvasPoint(s.Position);
            if (p.X < -40 || p.Y < -40 || p.X > size.X + 40 || p.Y > size.Y + 40) continue;
            Vector2 dir = G(OceanWorld.Unit(s.Velocity));
            if (s.Hostile) continue;
            if (s.Kind == WeaponKind.Mine)
            {
                DrawCircle(p,12,Navy); DrawCircle(p,8,new Color("a5b9ab"));
                for(int i=0;i<4;i++) { var d=Vector2.FromAngle(i*Mathf.Pi/2); DrawLine(p+d*7,p+d*15,Cream,3,true); }
                DrawCircle(p,3,s.Age>=.5f?Aqua:Cream);
                if(s.Age>=.5f) DrawArc(p,22+Mathf.Sin(Clock*5)*2,0,Mathf.Tau,24,new Color(Aqua,.3f),1.5f,true);
            }
            else if (s.Kind == WeaponKind.Arcane)
            {
                var magic = new Color("b6a0f4");
                if(orbTrails.TryGetValue(s,out var trail) && trail.Count>1)
                {
                    var points=trail.Select(point=>point-Camera+size/2).Append(p).ToArray();
                    var colors=Enumerable.Range(0,points.Length).Select(i=>new Color(magic,i/(float)points.Length*.65f)).ToArray();
                    DrawPolylineColors(points,colors,2.3f,true);
                }
                DrawLine(p-dir*22,p,new Color(magic,.3f),4,true);
                DrawCircle(p,12,new Color(magic,.16f)); DrawCircle(p,7,magic);
                DrawCircle(p-new Vector2(2,2),3,new Color("eee4ff"));
            }
            else if (s.Kind == WeaponKind.Cannon)
            { DrawLine(p-dir*18,p,new Color(Cream,.18f),2,true); DrawCircle(p,6,new Color(Navy,.8f)); DrawCircle(p-new Vector2(1,1),4,new Color(Cream,.7f)); }
            else { DrawLine(p - dir * (s.Kind == WeaponKind.Harpoon ? 26 : 16), p, s.Kind == WeaponKind.Harpoon ? Aqua : Cream, 5, true); DrawLine(p - dir * 8, p + dir * 3, Cream, 3, true); }
        }
        var boatPos = Menu ? new Vector2(size.X * .73f, size.Y * .57f) : CanvasPoint(Voyage.Position);
        if (Shake > 0) boatPos += new Vector2(MathF.Sin(Clock * 100), MathF.Cos(Clock * 90)) * Shake;

        float heading = Menu ? -.65f : Voyage.Heading;
        var target = Voyage.Enemies.Where(e=>e.Health>0 && System.Numerics.Vector2.DistanceSquared(e.Position,Voyage.Position)<570*570).OrderBy(e=>System.Numerics.Vector2.DistanceSquared(e.Position,Voyage.Position)).FirstOrDefault();
        var mount = Voyage.Position + new V2(MathF.Sin(heading), -MathF.Cos(heading)) * (48 * (Voyage.Boat == BoatKind.Cutter ? 153f / 145 : 163f / 145));
        float aim = target == null ? 0 : MathF.Atan2(target.Position.Y-mount.Y,target.Position.X-mount.X)+Mathf.Pi/2-heading;
        if (Menu)
        {
            art.Monster(new(size.X * .84f, size.Y * .26f), 150, EnemyKind.Crab, Clock);
            art.Monster(new(size.X * .85f, size.Y * .81f), 225, EnemyKind.Serpent, Clock);
        }
        foreach (var p in particles)
        {
            Vector2 at = p.P - Camera + size / 2; float alpha = p.Life / p.MaxLife;
            if (p.Kind is "aura" or "bulwark") { float r = Math.Max(1, p.Size * (1 - alpha * .75f)); DrawArc(at, r, 0, Mathf.Tau, 60, new Color(Aqua, alpha * .65f), p.Kind == "bulwark" ? 7 : 2, true); }
            else if (p.Kind == "pull")
            {
                var end = p.End-Camera+size/2;
                DrawLine(at,end,new Color(Cream,alpha*.8f),1.5f+p.Size*.4f,true);
                DrawArc(end,5+p.Size*2,0,Mathf.Tau,16,new Color(Cream,alpha),2,true);
            }
            else if (p.Kind == "arc") { Vector2 end = p.End - Camera + size / 2; DrawPolyline([at, at.Lerp(end, .3f) + new Vector2(0, 15), at.Lerp(end, .6f) - new Vector2(0, 12), end], new Color(Aqua, alpha*.7f), 2.5f, true); }
            else if (p.Kind == "ring") DrawArc(at, Math.Max(1, p.Size * (1 - alpha)), 0, Mathf.Tau, 40, new Color(p.Color, alpha), 4, true);
            else DrawCircle(at, p.Size * alpha, new Color(p.Color, alpha));
        }
        art.Boat(boatPos + new Vector2(0, MathF.Sin(Clock * 2.7f) * 1.4f), Menu ? 235 : Voyage.Boat == BoatKind.Cutter ? 153 : 163, heading, Voyage.Boat, Clock, Voyage.Weapons, Voyage.Invulnerable > 0 && (int)(Clock * 16) % 2 == 0, aim, muzzleTime > 0);
        // Threats stay above friendly effects and the hull, even in dense combat.
        foreach (var shot in Voyage.Shots)
        {
            if (!shot.Hostile || shot.Life <= 0) continue;
            var at = CanvasPoint(shot.Position);
            DrawCircle(at, 12, Navy); DrawCircle(at, 8, Coral);
            DrawCircle(at-new Vector2(2,2),2,Cream);
        }
        DrawMs = DrawMs * .95 + System.Diagnostics.Stopwatch.GetElapsedTime(drawStart).TotalMilliseconds * .05;
    }
    void DrawFishing(Place place, Vector2 p)
    {
        bool casting = Voyage.Mode == VoyageMode.Fishing && Voyage.FishingPlace?.Id == place.Id;
        if (Voyage.World.FishLeft(place) == 0 && !casting) return;
        DrawEllipse(p, new(60, 44), new Color(Aqua, .075f));
        DrawArc(p, 48, Clock*.15f, Clock*.15f+Mathf.Pi*.7f, 24, new Color(Aqua,.45f), 2, true);
        DrawArc(p, 48, Clock*.15f+Mathf.Pi, Clock*.15f+Mathf.Pi*1.7f, 24, new Color(Aqua,.25f), 2, true);
        for (int i = 0; i < 5; i++)
        {
            float a = i * Mathf.Tau / 5 + Clock * .22f;
            Vector2 fish = p + new Vector2(MathF.Cos(a) * 24, MathF.Sin(a) * 18);
            DrawSetTransform(fish, .3f*Mathf.Sin(a), Vector2.One * 1.25f);
            DrawColoredPolygon(Enumerable.Range(0,16).Select(point=>new Vector2(3+Mathf.Cos(point*Mathf.Tau/16)*12,6+Mathf.Sin(point*Mathf.Tau/16)*4)).ToArray(),new Color(Navy,.28f));
            DrawColoredPolygon([new(-8,0),new(-3,-4),new(4,-3),new(9,0),new(3,4),new(-3,3)],new Color("b8d5b5"));
            DrawColoredPolygon([new(-6,0),new(-13,-5),new(-12,5)],new Color("abc7aa"));
            DrawCircle(new(5,-.5f),1.1f,Navy);
            DrawSetTransform(Vector2.Zero);
        }
    }
    void DrawEllipse(Vector2 p, Vector2 radius, Color color) { DrawSetTransform(p, 0, radius); DrawCircle(Vector2.Zero, 1, color); DrawSetTransform(Vector2.Zero); }
}
