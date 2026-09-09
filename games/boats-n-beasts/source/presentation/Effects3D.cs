using Godot;
using BoatsNBeasts.Core;
using V2 = System.Numerics.Vector2;
namespace BoatsNBeasts;

// Presentation only. Samples actual simulation positions; never advances or changes the voyage.
public partial class Effects3D : Node3D
{
    static readonly Color Foam = new("bbdad2"), Aqua = new("68c4bc"), Coral = new("ef785d"), Cream = new("ffe0a3"), Magic = new("b59aed");
    static readonly Vector2[] FishFormation=[new(-.21f,-.29f),new(.16f,-.15f),new(-.055f,.01f),new(.25f,.22f),new(-.2f,.31f)];
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
    Mesh box = null!, sphere = null!, fishMesh = null!, barrelMesh = null!;
    StandardMaterial3D barrelMaterial = null!;
    StandardMaterial3D wood = null!, woodDark = null!, brass = null!;
    ShaderMaterial fish = null!;
    float time, sampleClock;
    int ballCount;
    bool initialized;
    public V2? Destination { get; set; }
    public int CachedEncounters => encounters.Count;
    public int TrailSamples => wake.Count + trails.Values.Sum(t => t.Count) + creatureWakes.Values.Sum(t => t.Count);
    public int ActiveParticles => sparks.Count + bursts.Count;
    readonly record struct Sample(Vector3 P, Vector3 Forward, float Born, float Speed);
    sealed class Burst { public string Kind = ""; public Vector3 P, End; public float Age, Life, Size; }
    sealed class Spark { public Vector3 P, V; public Color Color; public float Age, Life, Size; }
    sealed class Encounter { public Node3D Root = null!; public Place Place = null!; public readonly List<Node3D> Fish = new(); }
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
        fish = new ShaderMaterial { Shader = GD.Load<Shader>("res://source/presentation/EffectsFish.gdshader") };
        fishMesh = BuildFishMesh();
        barrelMesh = BuildBarrelMesh();
        barrelMaterial = new() { VertexColorUseAsAlbedo = true, VertexColorIsSrgb = true, Roughness = .9f };
    }
    public void Reset()
    {
        wake.Clear(); trails.Clear(); creatureWakes.Clear(); bursts.Clear(); sparks.Clear();
        foreach (var e in encounters.Values) e.Root.QueueFree(); encounters.Clear();
        time = sampleClock = 0; Destination = null;
        if (initialized) { foam.Begin(); foam.End(); solid.Begin(); solid.End(); balls.VisibleInstanceCount = 0; }
    }
    public void Sync(Voyage voyage, float clock, float dt)
    {
        EnsureReady();
        // `clock` may continue for menus. Transient animation follows the active voyage, including fishing.
        bool active = voyage.IsActive;
        float step = active ? Mathf.Clamp(dt, 0, .1f) : 0;
        time += step;
        fish.SetShaderParameter("school_time", time);
        if (step > 0)
        {
            foreach (var p in sparks) { p.Age += step; p.P += p.V * step; p.V *= MathF.Exp(-step * 2); p.V.Y -= step * 2.4f; }
            sparks.RemoveAll(p => p.Age >= p.Life);
            foreach (var b in bursts) b.Age += step;
            bursts.RemoveAll(b => b.Age >= b.Life);
            SampleTrails(voyage, step);
        }
        SyncEncounters(voyage);
        foam.Begin(); solid.Begin(); ballCount = 0;
        DrawWake(wake, .34f, 1.9f, 1);
        DrawWhirlpool(voyage);
        foreach (var enemy in voyage.Enemies)
        {
            if (enemy.Health <= 0) continue;
            if (creatureWakes.TryGetValue(enemy.Id, out var history)) DrawWake(history, enemy.Radius * .006f, .85f, .38f);
            DrawEmergence(enemy);
        }
        foreach (var shot in voyage.Shots) if (shot.Life > 0) DrawShot(shot);
        foreach (var b in bursts) DrawBurst(b);
        foreach (var p in sparks) Ball(p.P, Vector3.One * p.Size * (1 - p.Age / p.Life), p.Color);
        DrawEncounters(voyage);
        if (Destination is V2 destination)
        {
            var p = World(destination, .05f);
            foam.Arc(p, .12f, -.4f, 2.1f, .012f, Fade(Cream,.55f),10);
            foam.Arc(p, .12f, 2.8f, 1.9f, .012f, Fade(Cream,.55f),10);
        }
        foam.End(); solid.End(); balls.VisibleInstanceCount = ballCount;
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
            // Age widens the sampled path, so turns bend both branches rather than emitting straight V marks.
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
    void DrawShot(Shot s)
    {
        var p = World(s.Position, s.Kind == WeaponKind.Mine ? .1f : .24f);
        var dir = World(OceanWorld.Unit(s.Velocity),0)*100;
        if (s.Hostile)
        {
            float flight = Mathf.Clamp(s.Age / s.FlightDuration, 0, 1);
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
            Ball(p,Vector3.One*.12f,new("303e40")); Ball(p+new Vector3(-.022f,.033f,-.017f),Vector3.One*.045f,new("a8b1a6"));
            foam.Ribbon(p-dir*.25f,p-dir*.06f,.01f,.016f,Fade(Cream,.2f));
        }
        else if (s.Kind == WeaponKind.Harpoon)
        {
            var side=new Vector3(-dir.Z,0,dir.X); solid.Ribbon(p-dir*.29f,p,.019f,.026f,brass.AlbedoColor);
            solid.Triangle(p+dir*.075f,p-dir*.09f+side*.065f,p-dir*.06f-side*.065f,Cream);
        }
    }
    void DrawWhirlpool(Voyage v)
    {
        if (v.Mode == VoyageMode.Fishing || v.Weapons[(int)WeaponKind.Undertow] <= 0) return;
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
        if(ev.Kind is "arc" or "pull" or "aura" or "bulwark" or "explosion" or "calm" or "pufferExplosion" or "bossExplosion")
        {
            if(bursts.Count<192) bursts.Add(new() {Kind=ev.Kind,P=World(ev.Position,ev.Kind is "arc" or "pull"?.3f:.05f),End=World(ev.End,.3f),Life=ev.Kind is "arc" or "pull"?.2f:ev.Kind=="calm"?1.3f:ev.Kind is "pufferExplosion" or "bossExplosion"?.6f:.48f,Size=ev.Value*.01f});
        }
        int count=ev.Kind switch {"hit"=>2,"kill"=>7,"explosion"=>15,"hurt"=>5,"shot"=>3,"ricochet"=>4,"barrel"=>3,"catch" or "treasure" or "silver"=>6,"boostStart"=>9,_=>0};
        for(int i=0;i<count && sparks.Count<512;i++)
        {
            float a=random.RandfRange(0,Mathf.Tau), speed=random.RandfRange(.25f,ev.Kind=="explosion"?2.5f:1.2f);
            sparks.Add(new() {P=World(ev.Position,.18f),V=new(Mathf.Cos(a)*speed,random.RandfRange(.35f,1.1f),Mathf.Sin(a)*speed),Life=random.RandfRange(.16f,.4f),Size=random.RandfRange(.025f,.065f),Color=ev.Kind=="hurt"?Coral:ev.Kind=="boostStart"?Foam:Cream});
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
        if (b.Kind is "pufferExplosion" or "bossExplosion")
        {
            // Actual blast: a filled faceted upper hemisphere, never an aiming line.
            float blastRadius = b.Size;
            const int rings = 6, sides = 24;
            Vector3 Point(int ring, int side)
            {
                float latitude = ring * Mathf.Pi * .5f / rings, longitude = side * Mathf.Tau / sides;
                return b.P + new Vector3(Mathf.Cos(latitude) * Mathf.Cos(longitude), Mathf.Sin(latitude), Mathf.Cos(latitude) * Mathf.Sin(longitude)) * blastRadius;
            }
            for (int ring = 0; ring < rings; ring++)
                for (int side = 0; side < sides; side++)
                {
                    var a = Point(ring, side); var c = Point(ring + 1, side + 1);
                    var normal = ((a + c) * .5f - b.P).Normalized();
                    float light = .68f + .32f * Mathf.Max(0, normal.Dot(new Vector3(-.45f, .8f, -.4f).Normalized()));
                    var blastColor = Fade(new Color("ed4939") * light, alpha * .52f);
                    foam.Triangle(a, Point(ring, side + 1), c, blastColor);
                    foam.Triangle(a, c, Point(ring + 1, side), blastColor);
                }
            return;
        }
        if(b.Kind is "arc" or "pull")
        {
            var delta=b.End-b.P; var side=new Vector3(-delta.Z,0,delta.X).Normalized(); var last=b.P;
            int segments=b.Kind=="arc"?7:4;
            for(int i=1;i<=segments;i++)
            {
                var p=b.P.Lerp(b.End,i/(float)segments);
                if(i<segments) p+=side*(b.Kind=="arc"?(i%2==0?-.12f:.12f):.025f);
                foam.Ribbon(last,p,b.Kind=="arc"?.021f:.012f,b.Kind=="arc"?.021f:.012f,Fade(b.Kind=="arc"?Aqua:Cream,alpha*.85f)); last=p;
            }
            return;
        }
        float radius=b.Size>0?b.Size:1.3f;
        bool aura=b.Kind=="aura"; float r=radius*(aura?.82f+t*.18f:.3f+t*.7f);
        var color=b.Kind=="explosion"?Cream:Aqua;
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
            if(p.Kind is not (PlaceKind.Fishing or PlaceKind.Treasure or PlaceKind.Barrel)) continue;
            bool casting=v.Mode==VoyageMode.Fishing && v.FishingPlace?.Id==p.Id;
            if(v.World.Depletion.GetValueOrDefault(p.Id)>0 && !casting) continue;
            if(V2.DistanceSquared(v.Position,p.Position)>1800*1800) continue;
            livePlaces.Add(p.Id);
            if(!encounters.TryGetValue(p.Id,out var encounter))
            {
                encounter=new() {Root=new Node3D(),Place=p}; AddChild(encounter.Root); encounters[p.Id]=encounter;
                if(p.Kind==PlaceKind.Treasure) BuildTreasure(encounter.Root);
                else if(p.Kind==PlaceKind.Barrel) EffectsGeometry.Part(encounter.Root, barrelMesh, barrelMaterial, Vector3.Zero, Vector3.One);
                else BuildFish(encounter);
            }
            encounter.Root.Position=World(p.Position,p.Kind==PlaceKind.Barrel?.045f+Mathf.Sin(time*1.9f+p.Style%29)*.018f:p.Kind==PlaceKind.Treasure?.055f:.02f);
            encounter.Root.Rotation=p.Kind==PlaceKind.Barrel
                ? new(.08f, p.Style % 360 * Mathf.Pi / 180, Mathf.Sin(time*1.6f+p.Style%11)*.045f)
                : new(0, p.Kind==PlaceKind.Treasure?p.Heading:0, 0);
            if(p.Kind==PlaceKind.Fishing)
            {
                float phase=p.Style%19;
                for(int i=0;i<encounter.Fish.Count;i++)
                {
                    var node=encounter.Fish[i]; float row=i/2f;
                    uint h=SeedRandom.Hash(p.Style,i,7);
                    float x=FishFormation[i].X+(h%100)/100f*.08f-.04f, z=FishFormation[i].Y+((h>>8)%100)/100f*.08f-.04f;
                    node.Position=new(x+Mathf.Sin(time*.7f+row+phase)*.065f,.02f,z+Mathf.Sin(time*.55f+phase+row*.4f)*.06f);
                    node.Rotation=new(0,-.85f+Mathf.Sin(time*.85f+row)*.12f+(h%11)*.017f,0);
                }
            }
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
        // A continuous arched lid and gold frame distinguish the chest from floating barrels.
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
    void BuildFish(Encounter e)
    {
        // Shared tapered mesh and translucent water tint avoid lit white strokes on the opaque ocean.
        for(int i=0;i<5;i++)
        {
            var node=new Node3D();e.Root.AddChild(node);e.Fish.Add(node);
            float size=.8f+(SeedRandom.Hash(e.Place.Style,i,3)%100)*.004f;
            var part=EffectsGeometry.Part(node,fishMesh,fish,Vector3.Zero,Vector3.One*size);
            part.CastShadow=GeometryInstance3D.ShadowCastingSetting.Off;
        }
    }
    static ArrayMesh BuildFishMesh()
    {
        var st=new SurfaceTool();st.Begin(Mesh.PrimitiveType.Triangles);
        float[] z=[-.17f,-.125f,-.065f,.015f,.08f,.115f];
        float[] width=[.002f,.033f,.048f,.036f,.016f,.009f];
        Vector3 Ring(int row,int spoke)
        {
            float a=spoke*Mathf.Tau/8;
            return new(Mathf.Cos(a)*width[row],Mathf.Sin(a)*width[row]*.33f,z[row]);
        }
        void Tri(Vector3 a,Vector3 b,Vector3 c) {st.AddVertex(a);st.AddVertex(b);st.AddVertex(c);}
        for(int row=0;row<z.Length-1;row++) for(int spoke=0;spoke<8;spoke++)
        {
            var a=Ring(row,spoke);var b=Ring(row,(spoke+1)%8);var c=Ring(row+1,(spoke+1)%8);var d=Ring(row+1,spoke);
            Tri(a,c,b);Tri(a,d,c);
        }
        // Forked tail and pectoral fins broaden the silhouette beyond a thin bar.
        Tri(new(0,0,.1f),new(-.055f,0,.18f),new(0,0,.155f));
        Tri(new(0,0,.1f),new(0,0,.155f),new(.055f,0,.18f));
        Tri(new(-.033f,0,-.045f),new(-.075f,0,.005f),new(-.031f,0,-.002f));
        Tri(new(.033f,0,-.045f),new(.031f,0,-.002f),new(.075f,0,.005f));
        st.GenerateNormals();return st.Commit();
    }
    void DrawEncounters(Voyage v)
    {
        foreach(var e in encounters.Values)
        {
            if(e.Place.Kind==PlaceKind.Fishing) continue;
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
        foreach(var place in v.World.Places)
        {
            if(place.Kind!=PlaceKind.Current || V2.DistanceSquared(v.Position,place.Position)>1500*1500) continue;
            var center=World(place.Position,.028f);var dir=World(OceanWorld.FlowDirection(place),0)*100;var side=new Vector3(-dir.Z,0,dir.X);
            for(int lane=-1;lane<=1;lane++) for(int i=0;i<2;i++)
            {
                float x=((i*2.31f+time*.65f+lane*.57f+4.5f)%4.5f)-2.25f;
                float alpha=(1-Mathf.Abs(x)/2.25f)*.16f;
                Vector3 Point(float along)=>center+dir*along+side*(lane*.37f+Mathf.Sin(along*1.7f+lane)*.085f);
                var last=Point(x-.36f);
                // Sparse curved, tapered streaks travel with the current rather than making a dash grid.
                for(int segment=1;segment<=7;segment++)
                {
                    float t=segment/7f;var next=Point(x-.36f+t*.45f);
                    float width=.002f+Mathf.Sin(t*Mathf.Pi)*.008f;
                    foam.Ribbon(last,next,width,width,Fade(Aqua,alpha));last=next;
                }
            }
        }
        if(v.Mode==VoyageMode.Fishing && v.FishingPlace is {} fishing)
        {
            var start=World(v.Position,.45f);var end=World(fishing.Position,.045f);var middle=start.Lerp(end,.45f)+Vector3.Up*.22f;
            var last=start;
            for(int i=1;i<=12;i++) {float t=i/12f;var next=(1-t)*(1-t)*start+2*(1-t)*t*middle+t*t*end;foam.Ribbon(last,next,.006f,.006f,Fade(Cream,.55f));last=next;}
            Ball(end+Vector3.Up*.035f,new(.04f,.07f,.04f),Coral);
        }
    }
}
