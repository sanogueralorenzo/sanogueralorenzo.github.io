using Godot;
using BoatsNBeasts.Core;
using V2 = System.Numerics.Vector2;
namespace BoatsNBeasts;

// Presentation only. Samples actual simulation positions; never advances or changes the voyage.
public partial class Effects3D : Node3D
{
    static readonly Color Foam = new("bbdad2"), Aqua = new("68c4bc"), Coral = new("ef785d"), Cream = new("ffe0a3"), Magic = new("b59aed");
    readonly List<Sample> wake = new(80);
    readonly Dictionary<Shot, List<Sample>> trails = new();
    readonly Dictionary<int, List<Sample>> creatureWakes = new();
    readonly Dictionary<string, Encounter> encounters = new();
    readonly List<Burst> bursts = new(192);
    readonly List<Spark> sparks = new(512);
    readonly HashSet<Shot> liveShots = new();
    readonly HashSet<int> liveEnemies = new();
    readonly HashSet<string> livePlaces = new();
    readonly RandomNumberGenerator random = new() { Seed = 3819 };
    EffectsGeometry foam = null!, solid = null!;
    MultiMesh balls = null!;
    Mesh box = null!, sphere = null!, barrelMesh = null!;
    StandardMaterial3D barrelMaterial = null!;
    StandardMaterial3D wood = null!, woodDark = null!, brass = null!;
    float time, sampleClock;
    int ballCount;
    bool initialized;
    public SailCourse? Course { get; set; }
    public bool ShowBeacons { get; set; }
    public int CachedEncounters => encounters.Count;
    public int TrailSamples => wake.Count + trails.Values.Sum(t => t.Count) + creatureWakes.Values.Sum(t => t.Count);
    public int ActiveParticles => sparks.Count + bursts.Count;
    readonly record struct Sample(Vector3 P, Vector3 Forward, float Born, float Speed);
    sealed class Burst { public string Kind = ""; public Vector3 P, End; public float Age, Life, Size; }
    sealed class Spark { public Vector3 P, V; public Color Color; public float Age, Life, Size; }
    sealed class Encounter { public Node3D Root = null!; public Place Place = null!; }
    static Vector3 World(V2 p, float height = .035f) => new(p.X * .01f, height, p.Y * .01f);
    static Color Fade(Color color, float alpha) => new(color, Mathf.Clamp(alpha, 0, 1));

    void EnsureReady()
    {
        if (initialized) return;
        initialized = true; foam = new(this, true); solid = new(this, false);
        box = EffectsGeometry.BeveledBox();
        sphere = new SphereMesh { Radius = .5f, Height = 1, RadialSegments = 12, Rings = 6 };
        balls = new MultiMesh { TransformFormat = MultiMesh.TransformFormatEnum.Transform3D, UseColors = true, Mesh = sphere, InstanceCount = 1024, VisibleInstanceCount = 0 };
        AddChild(new MultiMeshInstance3D { Multimesh = balls, MaterialOverride = new StandardMaterial3D { VertexColorUseAsAlbedo = true, VertexColorIsSrgb = true, Roughness = .82f }, CastShadow = GeometryInstance3D.ShadowCastingSetting.Off });
        wood = EffectsGeometry.Matte("986039"); woodDark = EffectsGeometry.Matte("65452f"); brass = EffectsGeometry.Matte("d9ad55");
        barrelMesh = BuildBarrelMesh();
        barrelMaterial = new() { VertexColorUseAsAlbedo = true, VertexColorIsSrgb = true, Roughness = .9f };
    }
    public void Reset()
    {
        wake.Clear(); trails.Clear(); creatureWakes.Clear(); bursts.Clear(); sparks.Clear();
        foreach (var e in encounters.Values) e.Root.QueueFree(); encounters.Clear();
        time = sampleClock = 0;
        if (initialized) { foam.Begin(); foam.End(); solid.Begin(); solid.End(); balls.VisibleInstanceCount = 0; }
    }
    public void Sync(Voyage voyage, float clock, float dt)
    {
        EnsureReady();
        // Use voyage time for transient effects so menus pause them.
        bool active = voyage.Mode is VoyageMode.Sailing or VoyageMode.Victory or VoyageMode.Defeat;
        float step = active ? Mathf.Clamp(dt, 0, .1f) : 0;
        time += step;
        if (step > 0)
        {
            foreach (var p in sparks) { p.Age += step; p.P += p.V * step; p.V *= MathF.Exp(-step * 2); p.V.Y -= step * 2.4f; }
            sparks.RemoveAll(p => p.Age >= p.Life);
            foreach (var b in bursts) b.Age += step;
            bursts.RemoveAll(b => b.Age >= b.Life);
            if (voyage.IsActive) SampleTrails(voyage, step);
        }
        SyncEncounters(voyage);
        foam.Begin(); solid.Begin(); ballCount = 0;
        DrawWake(wake, voyage.IsBoosting ? .43f : .34f, 1.9f, voyage.IsBoosting ? 1.32f : 1);
        DrawWhirlpool(voyage);
        foreach (var enemy in voyage.Enemies)
        {
            if (enemy.Health <= 0) continue;
            if (creatureWakes.TryGetValue(enemy.Id, out var history)) DrawWake(history, enemy.Radius * .006f, .85f, .38f);
            DrawEmergence(enemy);
            if (enemy.GuardAnchor.HasValue && !enemy.Emerging)
                foam.Arc(World(enemy.Position), .79f, time * 2, 4.8f, .027f, Fade(Cream, .67f), 26);
            if (enemy.Drenched > 0)
            {
                var marked = World(enemy.Position, .069f);
                for (int arm = 0; arm < 2; arm++)
                    foam.Arc(marked, .13f + enemy.Radius * .01f, time * -2 + arm * Mathf.Pi,
                        1.75f, .025f, Fade(Magic, .72f), 9);
            }
            if (enemy.Fuse > 0)
                DrawWarning(enemy.Position, Enemy.PufferBlastRadius, 1 - enemy.Fuse / Enemy.PufferFuseDuration);
            if (enemy.Charge is { } charge)
                DrawCrownclawCharge(enemy, charge);
            else if (enemy.Telegraph > 0)
                DrawCharge(enemy);
            if (enemy.Kind == EnemyKind.Leviathan && enemy.Exposed > 0)
                DrawCrownclawOpening(enemy);
        }
        bool stormshot = voyage.ActiveCombo == WeaponCombo.Stormshot;
        foreach (var shot in voyage.Shots)
            if (shot.Life > 0) DrawShot(shot, stormshot);
        foreach (var b in bursts) DrawBurst(b);
        foreach (var p in sparks) Ball(p.P, Vector3.One * p.Size * (1 - p.Age / p.Life), p.Color);
        DrawEncounters(voyage);
        if (ShowBeacons)
        {
            DrawBeacons(voyage);
            if (voyage.SalvageAvailable) DrawSalvage(voyage);
            if (voyage.RepairsAvailable && voyage.Health < voyage.MaxHealth) DrawRepairBerth(voyage);
        }
        if (Course is { Destination: { } destination } course)
            DrawCourse(voyage.Position, course.Ahead, destination);
        foam.End(); solid.End(); balls.VisibleInstanceCount = ballCount;
    }
    void DrawCourse(V2 boat, ReadOnlySpan<V2> waypoints, V2 destination)
    {
        var from = World(boat, .063f);
        float remaining = 17;
        float offset = .78f;
        var ink = Fade(Cream, .54f);
        foreach (var waypoint in waypoints)
        {
            var to = World(waypoint, .063f);
            float length = from.DistanceTo(to);
            if (length < .001f) continue;
            var direction = (to - from) / length;
            float span = Math.Min(length, remaining);
            for (; offset < span; offset += .55f)
            {
                var a = from + direction * offset;
                var b = from + direction * Math.Min(offset + .25f, span);
                foam.Ribbon(a, b, .015f, .008f, ink);
            }
            offset -= length;
            remaining -= length;
            if (remaining <= 0) break;
            from = to;
        }

        var end = World(destination, .061f);
        foam.Arc(end, .24f, -.4f, 2.1f, .019f, Fade(Cream, .77f), 10);
        foam.Arc(end, .24f, 2.8f, 1.9f, .019f, Fade(Cream, .77f), 10);
    }

    void DrawBeacons(Voyage voyage)
    {
        foreach (var beacon in voyage.Beacons)
        {
            if (!beacon.Lit && voyage.BossSpawned) continue;
            var center = World(beacon.Position, .058f);
            float charge = beacon.Progress;
            float radius = Beacon.Radius * .01f;
            Color color = beacon.Lit ? NauticalPalette.Aqua : NauticalPalette.Gold;
            for (int i = 0; i < 8; i++)
            {
                float angle = i * Mathf.Tau / 8;
                foam.Arc(center, radius, angle + .08f, .63f, .026f, Fade(color, .47f), 10);
            }
            if (charge > 0)
                foam.Arc(center, radius - .08f, -Mathf.Pi / 2, Mathf.Tau * charge, .04f, Fade(color, .83f), 56);
            float wave = time * .36f % 1;
            foam.Arc(center, .34f + wave * 1.15f, 0, Mathf.Tau, .025f, Fade(color, .5f * (1 - wave)), 28);
        }
    }

    void DrawSalvage(Voyage voyage)
    {
        var crate = World(voyage.Salvage.Position, .10f);
        if (!voyage.Salvage.Towing)
        {
            float pulse = time * .58f % 1;
            foam.Arc(crate, .57f + pulse * .54f, 0, Mathf.Tau, .025f, Fade(Cream, .72f * (1 - pulse)), 28);
            return;
        }

        float tension = voyage.TowTension;
        var hook = World(voyage.TowHook, .20f);
        var rope = Cream.Lerp(Coral, Mathf.SmoothStep(.49f, .95f, tension));
        var side = new Vector3(crate.Z - hook.Z, 0, hook.X - crate.X).Normalized();
        var last = hook;
        for (int i = 1; i <= 9; i++)
        {
            float t = i / 9f;
            var next = hook.Lerp(crate, t) + side * (Mathf.Sin(t * Mathf.Pi) * .24f * (1 - tension));
            foam.Ribbon(last, next, .024f, .024f, Fade(rope, .92f));
            last = next;
        }
        if (voyage.DeliveryBeacon is { } beacon)
            foam.Arc(World(beacon.Position, .06f), SalvageCargo.DeliveryRadius * .01f,
                0, Mathf.Tau, .035f, Fade(Aqua, .77f), 48);
    }

    void DrawRepairBerth(Voyage voyage)
    {
        var center = World(StartingArea.RepairBerth, .08f);
        float radius = Voyage.RepairRadius * NativeStage3D.Unit;
        for (int side = 0; side < 4; side++)
            foam.Arc(center, radius, side * Mathf.Pi / 2 + .15f, 1.22f, .029f, Fade(Aqua, .76f), 14);
        if (!voyage.Repairing) return;

        foam.Arc(center, radius - .09f, -Mathf.Pi / 2, Mathf.Tau * voyage.RepairProgress, .045f, Fade(Cream, .94f), 48);
        var mooring = StartingArea.RepairMooring;
        var sternOffset = voyage.TowHook - voyage.Position;
        var deck = V2.Dot(mooring - voyage.Position, sternOffset) > 0 ? voyage.TowHook : voyage.Position - sternOffset;
        var dock = World(mooring, .22f);
        var attachment = World(deck, .32f);
        var slack = dock.Lerp(attachment, .55f) - Vector3.Up * .12f;
        foam.Ribbon(dock, slack, .017f, .017f, Fade(Cream, .9f));
        foam.Ribbon(slack, attachment, .017f, .017f, Fade(Cream, .9f));
    }

    void DrawWarning(V2 position, float radius, float progress)
    {
        var center = World(position, .075f);
        foam.Arc(center, radius * .01f, 0, Mathf.Tau, .041f, Fade(Coral, .72f), 48);
        foam.Arc(center, radius * .01f * Math.Max(.08f, progress), 0, Mathf.Tau, .023f, Fade(Cream, .62f), 32);
    }

    void DrawCharge(Enemy enemy)
    {
        var start = World(enemy.Position, .07f);
        var forward = new Vector3(enemy.Direction.X, 0, enemy.Direction.Y);
        var side = new Vector3(-forward.Z, 0, forward.X);
        const float length = 2.7f;
        float width = enemy.Radius * .01f;
        for (int i = 1; i <= 4; i++)
        {
            var point = start + forward * length * i / 4;
            foam.Ribbon(point - side * width - forward * .30f, point, .027f, .027f, Fade(Coral, .85f));
            foam.Ribbon(point + side * width - forward * .30f, point, .027f, .027f, Fade(Coral, .85f));
        }
    }

    void DrawCrownclawCharge(Enemy enemy, CrownclawCharge charge)
    {
        bool windingUp = enemy.Telegraph > 0;
        float intensity = windingUp ? 1 - enemy.Telegraph / charge.Windup : 1;
        var start = World(windingUp ? charge.Start : enemy.Position, .085f);
        var end = World(charge.End, .085f);
        var forward = new Vector3(enemy.Direction.X, 0, enemy.Direction.Y);
        var side = new Vector3(-forward.Z, 0, forward.X);
        float width = enemy.ContactRadius * NativeStage3D.Unit;
        float heading = Mathf.Atan2(forward.Z, forward.X);
        var boundary = Fade(Coral, .76f + .23f * intensity);
        var fill = Fade(Coral, .14f + .16f * intensity);
        foam.Ribbon(start, end, width, width, fill);
        foam.Ribbon(start - side * width, end - side * width, .027f, .027f, boundary);
        foam.Ribbon(start + side * width, end + side * width, .027f, .027f, boundary);
        for (int i = 0; i < 20; i++)
        {
            float angle = heading - Mathf.Pi / 2 + i * Mathf.Pi / 20;
            float next = angle + Mathf.Pi / 20;
            var a = new Vector3(Mathf.Cos(angle), 0, Mathf.Sin(angle)) * width;
            var b = new Vector3(Mathf.Cos(next), 0, Mathf.Sin(next)) * width;
            foam.Triangle(end, end + a, end + b, fill);
            foam.Triangle(start, start - a, start - b, fill);
            foam.Ribbon(end + a, end + b, .028f, .028f, boundary);
            foam.Ribbon(start - a, start - b, .028f, .028f, boundary);
        }
        float length = start.DistanceTo(end);
        for (float along = .56f; along < length; along += .87f)
        {
            var tip = start + forward * along;
            var tail = tip - forward * .28f;
            foam.Ribbon(tail - side * .34f, tip, .035f, .035f, Fade(Cream, .68f + .28f * intensity));
            foam.Ribbon(tail + side * .34f, tip, .035f, .035f, Fade(Cream, .68f + .28f * intensity));
        }
    }

    void DrawCrownclawOpening(Enemy enemy)
    {
        var center = World(enemy.Position, .083f);
        var color = enemy.Grounded ? NauticalPalette.Aqua : NauticalPalette.Gold;
        float opacity = Mathf.Clamp(enemy.Exposed * 2.8f, 0, 1);
        for (int i = 0; i < 5; i++)
            foam.Arc(center, 1.12f, i * Mathf.Tau / 5 + time * .34f, .72f, .042f, Fade(color, opacity * .88f), 9);
    }

    void SampleTrails(Voyage v, float dt)
    {
        wake.RemoveAll(s => time - s.Born > 2.15f);
        liveShots.Clear(); foreach (var s in v.Shots) if (!s.Hostile && s.Kind == WeaponKind.Arcane && s.Life > 0) liveShots.Add(s);
        foreach (var shot in trails.Keys.ToArray()) if (!liveShots.Contains(shot)) trails.Remove(shot);
        liveEnemies.Clear(); foreach (var e in v.Enemies) if (e.Health > 0) liveEnemies.Add(e.Id);
        foreach (var id in creatureWakes.Keys.ToArray()) if (!liveEnemies.Contains(id)) creatureWakes.Remove(id);
        sampleClock += dt; if (sampleClock < .045f) return; sampleClock %= .045f;
        var forward = new Vector3(Mathf.Sin(v.Heading), 0, -Mathf.Cos(v.Heading));
        if (v.Velocity.Length() > 20)
            AddSample(wake, new(World(v.Position) - forward * .64f, forward, time, v.Velocity.Length() * .01f), 64);
        foreach (var shot in liveShots)
        {
            if (!trails.TryGetValue(shot, out var history)) trails[shot] = history = new(20);
            AddSample(history, new(World(shot.Position,.21f), default, time, 0), 18);
        }
        foreach (var enemy in v.Enemies)
        {
            if (enemy.Health <= 0) continue;
            if (!creatureWakes.TryGetValue(enemy.Id,out var history)) creatureWakes[enemy.Id] = history = new(24);
            var p = World(enemy.Position); var d = history.Count > 0 ? p - history[^1].P : Vector3.Zero;
            if (d.LengthSquared() > .0001f)
            {
                var heading=d.Normalized();
                if(history.Count>0)
                {
                    // A dash reversal starts a new trail rather than folding two banks together.
                    if(history[^1].Forward.Dot(heading)<-.2f) history.Clear();
                    else heading=history[^1].Forward.Lerp(heading,.3f).Normalized();
                }
                AddSample(history,new(p,heading,time,1),24);
            }
            else if (history.Count == 0) AddSample(history, new(p, forward, time, 1), 24);
            history.RemoveAll(s => time - s.Born > 1);
        }
    }
    static void AddSample(List<Sample> history, Sample sample, int max)
    {
        if (history.Count > 0 && history[^1].P.DistanceSquaredTo(sample.P) > 16) history.Clear();
        history.Add(sample); if (history.Count > max) history.RemoveAt(0);
    }
    void DrawWake(List<Sample> history, float width, float life, float strength)
    {
        for (int i = 1; i < history.Count; i++)
        {
            var a = history[i-1]; var b = history[i]; float age = time - b.Born;
            if (age > life) continue;
            float opacity = MathF.Pow(1 - age / life, 1.4f) * strength;
            var sideA = new Vector3(-a.Forward.Z,0,a.Forward.X); var sideB = new Vector3(-b.Forward.Z,0,b.Forward.X);
            // Widen the recorded path with age so both wake branches follow turns.
            float spreadA = width + (time-a.Born)*.22f; float spreadB = width + age*.22f;
            for (int sign = -1; sign <= 1; sign += 2)
            {
                var pa=a.P+sideA*spreadA*sign; var pb=b.P+sideB*spreadB*sign;
                float taper=Mathf.Sin(Mathf.Pi*Mathf.Clamp(age/life,0,1));
                float previousTaper=Mathf.Sin(Mathf.Pi*Mathf.Clamp((time-a.Born)/life,0,1));
                if(pa.DistanceTo(pb)>a.P.DistanceTo(b.P)*2+.08f) continue;
                // Adjacent pieces share their bank vertices, avoiding gaps at curved joins.
                float wa=.05f*previousTaper, wb=.05f*taper;
                var color=Fade(Aqua,opacity*.7f);
                foam.Triangle(pa+sideA*wa,pb+sideB*wb,pb-sideB*wb,color);
                foam.Triangle(pa+sideA*wa,pb-sideB*wb,pa-sideA*wa,color);
            }
        }
    }
    void DrawShot(Shot s, bool stormshot)
    {
        float height = s.Kind == WeaponKind.Mine ? .1f : .24f;
        if (s.LaunchHeight > 0) height = Mathf.Lerp(s.LaunchHeight, height, Math.Min(1, s.Age / .26f));
        var p = World(s.Position, height);
        var dir = World(OceanWorld.Unit(s.Velocity),0)*100;
        if (s.Hostile)
        {
            float flight = Mathf.Clamp(s.Age / s.FlightDuration, 0, 1);
            DrawWarning(s.Target, s.Radius, flight);
            p.Y = .12f + .4f * (1 - flight) + Mathf.Sin(flight * Mathf.Pi) * 1.8f;
            Ball(p, Vector3.One * .27f, new("733b3c"));
            Ball(p + new Vector3(-.025f, .07f, -.025f), Vector3.One * .20f, Coral);
            Ball(p + Vector3.Up * .17f, Vector3.One * .055f, Cream);
            return;
        }
        if (s.Kind == WeaponKind.Arcane)
        {
            if (trails.TryGetValue(s,out var trail))
            {
                for (int i = 1; i < trail.Count; i++)
                {
                    float alpha = i/(float)trail.Count; var a = trail[i-1].P; var b = trail[i].P;
                    foam.Ribbon(a,b,.012f*alpha,.022f*alpha,Fade(Magic,alpha*.55f));
                    if (i%4 == 0) Ball(a+new Vector3(.018f,.015f,0),Vector3.One*.025f*alpha,Magic);
                }
                if(trail.Count>0) foam.Ribbon(trail[^1].P,p,.019f,.027f,Fade(Magic,.55f));
            }
            Ball(p,Vector3.One*.17f,new("7958ad")); Ball(p+new Vector3(-.02f,.043f,-.015f),Vector3.One*.1f,Magic);
            Ball(p+new Vector3(-.034f,.077f,-.025f),Vector3.One*.04f,new("e5d5fa"));
        }
        else if (s.Kind == WeaponKind.Mine)
        {
            Ball(p,Vector3.One*.25f,new("304a50"));
            for (int i=0;i<4;i++) { float a=i*Mathf.Pi*.5f; Ball(p+new Vector3(Mathf.Cos(a),0,Mathf.Sin(a))*.14f,Vector3.One*.062f,brass.AlbedoColor); }
            Ball(p+Vector3.Up*.12f,Vector3.One*.065f,s.Age>=.5f?Coral:Cream);
        }
        else if (s.Kind == WeaponKind.Cannon)
        {
            bool charged = stormshot && s.Ricocheted && !s.ComboSpent;
            Ball(p, Vector3.One * .12f, charged ? Aqua : new Color("303e40"));
            Ball(p + new Vector3(-.022f, .033f, -.017f), Vector3.One * .045f, charged ? Cream : new Color("a8b1a6"));
            foam.Ribbon(p - dir * (charged ? .43f : .25f), p - dir * .06f, .01f, .016f,
                charged ? Fade(Aqua, .76f) : Fade(Cream, .2f));
        }
        else if (s.Kind == WeaponKind.Harpoon)
        {
            var side=new Vector3(-dir.Z,0,dir.X); solid.Ribbon(p-dir*.29f,p,.019f,.026f,brass.AlbedoColor);
            solid.Triangle(p+dir*.075f,p-dir*.09f+side*.065f,p-dir*.06f-side*.065f,Cream);
        }
    }
    void DrawWhirlpool(Voyage v)
    {
        if (v.Weapons[(int)WeaponKind.Undertow] <= 0) return;
        var center = World(v.Position, .046f); float radius = v.WhirlpoolRadius * .01f;
        // Five separated curls keep the actual attack extent visible without a solid HUD circle.
        for (int arm = 0; arm < 5; arm++)
        {
            float start = time * .7f + arm * Mathf.Tau / 5;
            var last = center + new Vector3(Mathf.Cos(start),0,Mathf.Sin(start)) * radius * .94f;
            for (int i=1;i<=14;i++)
            {
                float t=i/14f, angle=start+t*.67f;
                float r=radius*(.94f+.06f*Mathf.Sin(t*Mathf.Pi*.5f));
                var next=center+new Vector3(Mathf.Cos(angle),0,Mathf.Sin(angle))*r;
                float fade=Mathf.Sin(t*Mathf.Pi);
                foam.Ribbon(last,next,.012f,.014f,Fade(Aqua,.25f*fade)); last=next;
            }
        }
    }
    void DrawEmergence(Enemy e)
    {
        if (!e.Emerging) return;
        var p = World(e.Position, .065f);
        float t = e.Time / Enemy.EmergenceDuration;
        float radius = e.Radius * .01f * (.7f + t * .5f);
        foam.Arc(p, radius, e.Id, 1.2f, .016f, Fade(Foam, (1 - t) * .6f));
        foam.Arc(p, radius, e.Id + 3.1f, 1.7f, .016f, Fade(Foam, (1 - t) * .5f));
    }
    void Ball(Vector3 p, Vector3 scale, Color color)
    {
        if(ballCount>=1024 || scale.X<.002f) return;
        balls.SetInstanceTransform(ballCount,new Transform3D(Basis.Identity.Scaled(scale),p));
        balls.SetInstanceColor(ballCount++,color);
    }
    public void Effect(GameEvent ev)
    {
        if (ev.Kind == "barrel" && bursts.Count < 192)
            bursts.Add(new() { Kind = "barrel", P = World(ev.Position, .06f), Life = .55f });
        bool link = ev.Kind is "arc" or "pull" or "tripwire";
        if (bursts.Count < 192 && (link || ev.Kind is "aura" or "bulwark" or "explosion" or "calm"
            or "pufferExplosion" or "bossExplosion" or "crownclawGrounded" or "repairDone" or "beacon" or "broadside" or "blink" or "stormshot" or "riptide"))
        {
            float life = ev.Kind switch
            {
                "arc" or "pull" => .2f,
                "tripwire" => .34f,
                "calm" => 1.3f,
                "pufferExplosion" or "bossExplosion" or "crownclawGrounded" => .6f,
                _ => .48f
            };
            bursts.Add(new()
            {
                Kind = ev.Kind, P = World(ev.Position, link ? .26f : .05f), End = World(ev.End, .26f),
                Life = life, Size = (ev.Kind == "beacon" ? Beacon.Radius : ev.Value) * .01f
            });
        }
        int count=ev.Kind switch {"hit"=>2,"kill"=>7,"explosion"=>15,"hurt"=>5,"shot"=>3,"ricochet"=>4,"barrel"=>3,"heal" or "treasure" or "silver"=>6,"boostStart"=>9,"beacon" or "towDelivered" or "crownclawGrounded"=>26,"towHooked" or "towSnapped"=>8,"chain"=>13,"broadside"=>20,"blink"=>16,"stormshot"=>14,"riptide"=>7,_=>0};
        for(int i=0;i<count && sparks.Count<512;i++)
        {
            float a=random.RandfRange(0,Mathf.Tau), speed=random.RandfRange(.25f,ev.Kind=="explosion"?2.5f:1.2f);
            float height = ev.Kind is "shot" or "harpoon" ? ev.Value : .18f;
            sparks.Add(new() {P=World(ev.Position,height),V=new(Mathf.Cos(a)*speed,random.RandfRange(.35f,1.1f),Mathf.Sin(a)*speed),Life=random.RandfRange(.16f,.4f),Size=random.RandfRange(.025f,.065f),Color=ev.Kind=="hurt"?Coral:ev.Kind=="boostStart"?Foam:Cream});
        }
    }
    void DrawBurst(Burst b)
    {
        float t=b.Age/b.Life, alpha=1-t;
        if (b.Kind == "barrel")
        {
            for (int i = 0; i < 6; i++)
            {
                float angle = i * Mathf.Tau / 6 + .3f;
                var direction = new Vector3(Mathf.Cos(angle), 0, Mathf.Sin(angle));
                var p = b.P + direction * (.15f + t * .42f) + Vector3.Up * Mathf.Sin(t * Mathf.Pi) * .25f;
                var edge = new Vector3(-direction.Z, .6f, direction.X) * .04f * alpha;
                var tip = direction * .11f * alpha;
                solid.Triangle(p - edge - tip, p + edge - tip, p + edge + tip, new Color("986039"));
                solid.Triangle(p - edge - tip, p + edge + tip, p - edge + tip, new Color("986039"));
            }
            foam.Arc(b.P, .28f + t * .48f, .3f, 4.8f, .02f, Fade(Foam, alpha * .45f));
            return;
        }
        if (b.Kind is "pufferExplosion" or "bossExplosion" or "crownclawGrounded")
        {
            var wave = b.Kind == "crownclawGrounded" ? Foam : Coral;
            float blastRadius = b.Size * Mathf.Lerp(.48f, 1, Mathf.SmoothStep(0, 1, Math.Min(1, t * 2.6f)));
            foam.Arc(b.P, blastRadius, 0, Mathf.Tau, .045f * alpha + .01f, Fade(wave, alpha * .83f), 52);
            for (int i = 0; i < 10; i++)
            {
                float angle = i * Mathf.Tau / 10 + .22f;
                var direction = new Vector3(Mathf.Cos(angle), 0, Mathf.Sin(angle));
                var basePoint = b.P + direction * (blastRadius * .70f);
                float height = Mathf.Sin(t * Mathf.Pi) * (.18f + (i % 3) * .09f);
                var crest = b.P + direction * (blastRadius * .94f) + Vector3.Up * height;
                foam.Ribbon(basePoint, crest, .046f * alpha, .012f, Fade(Cream, alpha * .74f));
                foam.Arc(b.P, blastRadius * .77f, angle, .41f, .021f, Fade(wave, alpha * .46f), 7);
            }
            return;
        }
        if(b.Kind is "arc" or "pull" or "tripwire")
        {
            var delta=b.End-b.P; var side=new Vector3(-delta.Z,0,delta.X).Normalized(); var last=b.P;
            int segments=b.Kind=="arc"?7:4;
            for(int i=1;i<=segments;i++)
            {
                var p=b.P.Lerp(b.End,i/(float)segments);
                if(i<segments) p+=side*(b.Kind=="arc"?(i%2==0?-.12f:.12f):.025f);
                foam.Ribbon(last,p,b.Kind=="arc"?.021f:.012f,b.Kind=="arc"?.021f:.012f,Fade(b.Kind == "arc" ? Aqua : b.Kind == "tripwire" ? NauticalPalette.Gold : Cream, alpha * .85f)); last=p;
            }
            return;
        }
        if (b.Kind == "blink")
        {
            foam.Ribbon(b.P, b.End, .37f * alpha, .12f * alpha, Fade(Magic, .7f * alpha));
            foam.Arc(b.End, .20f + t, 0, Mathf.Tau, .03f, Fade(Magic, alpha), 24);
            return;
        }
        float radius=b.Size>0?b.Size:1.3f;
        bool aura=b.Kind=="aura"; float r=radius*(aura?.82f+t*.18f:.3f+t*.7f);
        var color = b.Kind switch
        {
            "explosion" or "beacon" or "broadside" or "stormshot" => Cream,
            "riptide" => Magic,
            _ => Aqua
        };
        int arms=aura?3:5;
        for(int i=0;i<arms;i++)
        {
            float start=i*Mathf.Tau/arms+t*(aura?1.5f:.2f);
            foam.Arc(b.P,r,start,aura?1.45f:.68f,aura?.018f:.025f,Fade(color,alpha*(aura?.38f:.65f)),18);
        }
    }

    void SyncEncounters(Voyage v)
    {
        livePlaces.Clear();
        foreach(var p in v.World.Places)
        {
            if(p.Kind is not (PlaceKind.Treasure or PlaceKind.Barrel)) continue;
            if(v.World.Depletion.GetValueOrDefault(p.Id)>0) continue;
            if(V2.DistanceSquared(v.Position,p.Position)>1800*1800) continue;
            livePlaces.Add(p.Id);
            if(!encounters.TryGetValue(p.Id,out var encounter))
            {
                encounter=new() {Root=new Node3D(),Place=p}; AddChild(encounter.Root); encounters[p.Id]=encounter;
                if(p.Kind==PlaceKind.Treasure) BuildTreasure(encounter.Root);
                else if(p.Kind==PlaceKind.Barrel) EffectsGeometry.Part(encounter.Root, barrelMesh, barrelMaterial, Vector3.Zero, Vector3.One);
            }
            encounter.Root.Position=World(p.Position,p.Kind==PlaceKind.Barrel?.045f+Mathf.Sin(time*1.9f+p.Style%29)*.018f:p.Kind==PlaceKind.Treasure?.055f:.02f);
            encounter.Root.Rotation=p.Kind==PlaceKind.Barrel
                ? new(.08f, p.Style % 360 * Mathf.Pi / 180, Mathf.Sin(time*1.6f+p.Style%11)*.045f)
                : new(0, p.Kind==PlaceKind.Treasure?p.Heading:0, 0);
        }
        foreach(var id in encounters.Keys.ToArray()) if(!livePlaces.Contains(id)) {encounters[id].Root.QueueFree();encounters.Remove(id);}
    }
    void BuildTreasure(Node3D root)
    {
        EffectsGeometry.Part(root,box,woodDark,new(0,.14f,0),new(.54f,.26f,.4f));
        for(int i=0;i<3;i++)
        {
            foreach(float z in new[]{-.201f,.201f}) EffectsGeometry.Part(root,box,wood,new(0,.062f+i*.078f,z),new(.52f,.067f,.024f));
        }
        EffectsGeometry.Part(root,ChestArch(.54f,.204f,true),woodDark,new(0,.27f,0),Vector3.One);
        const int slats=9;
        for(int i=0;i<slats;i++)
            EffectsGeometry.Part(root,ChestArch(.536f,.208f,false,-Mathf.Pi*.5f+i*Mathf.Pi/slats+.008f,Mathf.Pi/slats-.016f),wood,new(0,.27f,0),Vector3.One);
        foreach(float x in new[]{-.18f,.18f})
        {
            EffectsGeometry.Part(root,ChestArch(.04f,.219f,false),brass,new(x,.27f,0),Vector3.One);
            foreach(float z in new[]{-.219f,.219f})
            {
                EffectsGeometry.Part(root,box,brass,new(x,.14f,z),new(.041f,.26f,.025f));
                foreach(float y in new[]{.07f,.205f}) EffectsGeometry.Part(root,sphere,brass,new(x,y,z+Mathf.Sign(z)*.016f),new(.022f,.022f,.016f));
            }
        }
        foreach (float z in new[] { -.216f, .216f })
            EffectsGeometry.Part(root,box,brass,new(0,.265f,z),new(.54f,.04f,.027f));
        EffectsGeometry.Part(root,box,brass,new(0,.278f,.222f),new(.075f,.115f,.03f));
        EffectsGeometry.Part(root,box,brass,new(0,.239f,.246f),new(.062f,.074f,.03f));
        EffectsGeometry.Part(root,sphere,woodDark,new(0,.24f,.266f),new(.014f,.025f,.007f));
    }
    static ArrayMesh BuildBarrelMesh()
    {
        var st = new SurfaceTool(); st.Begin(Mesh.PrimitiveType.Triangles);
        void Triangle(Vector3 a, Vector3 b, Vector3 c, Color color)
        {
            var normal = (b-a).Cross(c-a).Normalized();
            st.SetColor(color); st.SetNormal(normal);
            st.AddVertex(a); st.AddVertex(c); st.AddVertex(b);
        }
        Vector3 Point(float x, float r, float angle) => new(x, Mathf.Cos(angle)*r, Mathf.Sin(angle)*r);
        void Strip(float x0, float x1, float r0, float r1, bool metal)
        {
            for (int i=0;i<12;i++)
            {
                float a=i*Mathf.Tau/12+(metal?0:.012f), b=(i+1)*Mathf.Tau/12-(metal?0:.012f);
                var p=Point(x0,r0,a); var q=Point(x1,r1,a); var r=Point(x1,r1,b); var s=Point(x0,r0,b);
                var color=metal?new Color("586268"):new Color(i%3==0?"ad7545":"966039");
                Triangle(p,s,r,color); Triangle(p,r,q,color);
            }
        }
        float[] xs=[-.31f,-.23f,0,.23f,.31f], radii=[.185f,.225f,.24f,.225f,.185f];
        for(int i=0;i<4;i++) Strip(xs[i],xs[i+1],radii[i],radii[i+1],false);
        Strip(-.25f,-.20f,.226f,.237f,true); Strip(.20f,.25f,.237f,.226f,true);
        for(int end=-1;end<=1;end+=2) for(int i=0;i<12;i++)
        {
            var a=Point(end*.312f,.182f,i*Mathf.Tau/12); var b=Point(end*.312f,.182f,(i+1)*Mathf.Tau/12);
            if(end>0) Triangle(new(end*.312f,0,0),a,b,new Color("795234"));
            else Triangle(new(end*.312f,0,0),b,a,new Color("795234"));
        }
        void Mark(float x, float z, float w, float d)
        {
            var a = new Vector3(x-w/2, .245f, z-d/2); var b = new Vector3(x+w/2, .245f, z-d/2);
            var c = new Vector3(x+w/2, .245f, z+d/2); var e = new Vector3(x-w/2, .245f, z+d/2);
            Triangle(a, c, b, Aqua); Triangle(a, e, c, Aqua);
        }
        Mark(0, 0, .25f, .065f); Mark(0, 0, .065f, .22f);
        return st.Commit();
    }
    static ArrayMesh ChestArch(float length,float radius,bool caps,float start=-Mathf.Pi*.5f,float sweep=Mathf.Pi)
    {
        var st=new SurfaceTool();st.Begin(Mesh.PrimitiveType.Triangles);
        void Triangle(Vector3 a,Vector3 b,Vector3 c,Vector3 na,Vector3 nb,Vector3 nc)
        {st.SetNormal(na);st.AddVertex(a);st.SetNormal(nb);st.AddVertex(b);st.SetNormal(nc);st.AddVertex(c);}
        int segments=Math.Max(3,(int)(24*sweep/Mathf.Pi));
        for(int i=0;i<segments;i++)
        {
            float a=start+sweep*i/segments,b=start+sweep*(i+1)/segments;
            var n0=new Vector3(0,Mathf.Cos(a),Mathf.Sin(a));var n1=new Vector3(0,Mathf.Cos(b),Mathf.Sin(b));
            var p0=n0*radius-Vector3.Right*length*.5f;var p1=n0*radius+Vector3.Right*length*.5f;
            var p2=n1*radius+Vector3.Right*length*.5f;var p3=n1*radius-Vector3.Right*length*.5f;
            Triangle(p0,p1,p2,n0,n0,n1);Triangle(p0,p2,p3,n0,n1,n1);
            if(caps)
            {
                Triangle(-Vector3.Right*length*.5f,p0,p3,Vector3.Left,Vector3.Left,Vector3.Left);
                Triangle(Vector3.Right*length*.5f,p2,p1,Vector3.Right,Vector3.Right,Vector3.Right);
            }
        }
        return st.Commit();
    }
    void DrawEncounters(Voyage v)
    {
        foreach(var e in encounters.Values)
        {
            if (e.Place.Kind==PlaceKind.Treasure)
            {
                float gleam=Mathf.Pow(Mathf.Max(0,Mathf.Sin(time*1.5f+e.Place.Style%13)),10);
                var center=World(e.Place.Position,.64f);
                var color=Fade(Cream,gleam*.75f);
                foam.Ribbon(center-Vector3.Right*.10f,center+Vector3.Right*.10f,.012f,.012f,color);
                foam.Ribbon(center-Vector3.Back*.10f,center+Vector3.Back*.10f,.012f,.012f,color);
                continue;
            }
            var p=World(e.Place.Position,.034f);float radius=.32f;
            foam.Arc(p,radius,time*.3f+e.Place.Style%13,.95f,.009f,Fade(Foam,.24f));
            foam.Arc(p,radius*1.1f,time*.3f+e.Place.Style%13+3.2f,.65f,.008f,Fade(Foam,.2f));
        }
        foreach (var place in v.World.Places)
        {
            if (place.Kind != PlaceKind.Current || V2.DistanceSquared(v.Position, place.Position) > 1500 * 1500) continue;
            DrawCurrent(place);
        }
    }

    void DrawCurrent(Place place)
    {
        var center = World(place.Position, .036f);
        var along = World(OceanWorld.FlowDirection(place), 0) / NativeStage3D.Unit;
        var across = new Vector3(-along.Z, 0, along.X);
        float radius = place.Radius * NativeStage3D.Unit;
        for (int lane = -1; lane <= 1; lane++)
        {
            float offset = lane * .145f * radius;
            float span = radius * (lane == 0 ? .92f : .75f);
            for (int streak = 0; streak < 2; streak++)
            {
                float phase = (1 + time * .29f + lane * .13f + streak * .5f) % 1;
                float start = Mathf.Lerp(-span, span, phase);
                Color color = Fade(new("9edfcc"), Mathf.Sin(phase * Mathf.Pi) * .40f);
                Vector3 Point(float s) => center + along * s + across * (offset + Mathf.Sin(s * 1.7f + lane) * .065f);
                var last = Point(start - .45f);
                for (int i = 1; i <= 7; i++)
                {
                    float t = i / 7f;
                    var next = Point(start - .45f + t * .68f);
                    float width = .005f + Mathf.Sin(t * Mathf.Pi) * .018f;
                    foam.Ribbon(last, next, width, width, color);
                    last = next;
                }
                if (lane == 0)
                {
                    var shoulder = Point(start + .055f);
                    var tip = Point(start + .242f);
                    foam.Ribbon(shoulder + across * .12f, tip, .013f, .010f, color);
                    foam.Ribbon(shoulder - across * .12f, tip, .013f, .010f, color);
                }
            }
        }
    }

}
