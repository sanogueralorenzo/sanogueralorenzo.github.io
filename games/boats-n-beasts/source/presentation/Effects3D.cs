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
    Mesh box = null!, sphere = null!;
    StandardMaterial3D wood = null!, woodDark = null!, brass = null!, sail = null!, fish = null!;
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
        AddChild(new MultiMeshInstance3D { Multimesh = balls, MaterialOverride = new StandardMaterial3D { VertexColorUseAsAlbedo = true, Roughness = .82f }, CastShadow = GeometryInstance3D.ShadowCastingSetting.Off });
        wood = EffectsGeometry.Matte("a87145"); woodDark = EffectsGeometry.Matte("65452f"); brass = EffectsGeometry.Matte("c5a464"); sail = EffectsGeometry.Matte("c9c3a1");
        fish = EffectsGeometry.Matte("487f85");
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
        // `clock` may continue for menus. All transient animation uses this sailing-only clock.
        bool sailing = voyage.Mode == VoyageMode.Sailing;
        float step = sailing ? Mathf.Clamp(dt, 0, .1f) : 0;
        time += step;
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
        DrawWake(wake, .29f, 1.9f, 1);
        foreach (var enemy in voyage.Enemies)
        {
            if (enemy.Health <= 0) continue;
            if (creatureWakes.TryGetValue(enemy.Id, out var history)) DrawWake(history, enemy.Radius * .006f, .85f, .38f);
            DrawTelegraph(voyage, enemy);
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
            AddSample(wake, new(World(v.Position) - forward * .43f, forward, time, v.Velocity.Length() * .01f), 64);
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
            if (d.LengthSquared() > .0001f) AddSample(history, new(p, d.Normalized(), time, 1), 24);
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
            float lineWidth = (.012f + age*.012f) * Mathf.Clamp(b.Speed, .7f, 1.6f);
            for (int sign = -1; sign <= 1; sign += 2)
            {
                var pa = a.P + sideA * spreadA * sign; var pb = b.P + sideB * spreadB * sign;
                // Uneven gaps and fine companion flecks keep the foam broken and organic.
                if ((i + (sign+1)*3) % 9 != 0) foam.Ribbon(pa,pb,lineWidth,lineWidth*.85f,Fade(Foam,opacity*.63f));
                if (i%3 == 0) foam.Ribbon(pa+sideA*.055f*sign,pb.Lerp(pa,.5f)+sideB*.07f*sign,.009f,.006f,Fade(Foam,opacity*.45f));
            }
            if (i%4 == 0) foam.Ribbon(a.P,b.P,.04f,.025f,Fade(Aqua,opacity*.08f));
        }
    }
    void DrawShot(Shot s)
    {
        var p = World(s.Position, s.Kind == WeaponKind.Mine ? .1f : .24f);
        var dir = World(OceanWorld.Unit(s.Velocity),0)*100;
        if (s.Hostile)
        {
            Ball(p,new(.19f,.16f,.19f),new("733b3c")); Ball(p+new Vector3(-.015f,.055f,-.015f),Vector3.One*.135f,Coral);
            foam.Ribbon(p-dir*.23f,p-dir*.075f,.016f,.035f,Fade(Coral,.48f)); return;
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
    void DrawTelegraph(Voyage v, Enemy e)
    {
        var p=World(e.Position,.065f);
        if(e.Emerging)
        {
            float t=e.Time/Enemy.EmergenceDuration;
            foam.Arc(p,e.Radius*.01f*(.7f+t*.5f),e.Id,1.2f,.016f,Fade(Foam,(1-t)*.6f));
            foam.Arc(p,e.Radius*.01f*(.7f+t*.5f),e.Id+3.1f,1.7f,.016f,Fade(Foam,(1-t)*.5f));
        }
        if(e.Telegraph<=0) return;
        float opacity=.7f+.15f*Mathf.Sin(time*20); float radius=e.Radius*.01f+.13f;
        // Coral arcs are attack tells, not ambient decorative rings.
        for(int i=0;i<4;i++) foam.Arc(p,radius,i*Mathf.Pi*.5f+.1f,1.3f,.023f,Fade(Coral,opacity));
        var direction=e.Kind==EnemyKind.Serpent?e.Direction:OceanWorld.Unit(v.Position-e.Position);
        var dir=World(direction,0)*100; var side=new Vector3(-dir.Z,0,dir.X);
        if(e.Kind==EnemyKind.Serpent)
        {
            var end=p+dir*2.3f;
            foam.Ribbon(p+dir*radius,end,.13f,.16f,Fade(Coral,.13f));
            foam.Ribbon(p+dir*radius+side*.15f,end+side*.15f,.011f,.017f,Fade(Coral,.6f));
            foam.Ribbon(p+dir*radius-side*.15f,end-side*.15f,.011f,.017f,Fade(Coral,.6f));
        }
        else if(e.Kind is EnemyKind.Ray or EnemyKind.Puffer)
        {
            int fan=e.Kind==EnemyKind.Ray?1:0;
            for(int i=-fan;i<=fan;i++) { var d=dir.Rotated(Vector3.Up,i*.24f); foam.Ribbon(p+d*radius,p+d*(radius+.68f),.018f,.009f,Fade(Coral,.5f)); }
        }
    }
    void Ball(Vector3 p, Vector3 scale, Color color)
    {
        if(ballCount>=1024 || scale.X<.002f) return;
        balls.SetInstanceTransform(ballCount,new Transform3D(Basis.Identity.Scaled(scale),p));
        balls.SetInstanceColor(ballCount++,color);
    }
    public void Effect(GameEvent ev)
    {
        if(ev.Kind is "arc" or "pull" or "aura" or "bulwark" or "explosion" or "slam" or "calm")
        {
            if(bursts.Count<192) bursts.Add(new() {Kind=ev.Kind,P=World(ev.Position,ev.Kind is "arc" or "pull"?.3f:.05f),End=World(ev.End,.3f),Life=ev.Kind is "arc" or "pull"?.2f:ev.Kind=="calm"?1.3f:.48f,Size=ev.Value*.01f});
        }
        int count=ev.Kind switch {"hit"=>2,"kill"=>7,"explosion"=>15,"hurt"=>5,"shot"=>3,"ricochet"=>4,"catch" or "treasure" or "salvage" or "silver"=>6,"boostStart"=>9,_=>0};
        for(int i=0;i<count && sparks.Count<512;i++)
        {
            float a=random.RandfRange(0,Mathf.Tau), speed=random.RandfRange(.25f,ev.Kind=="explosion"?2.5f:1.2f);
            sparks.Add(new() {P=World(ev.Position,.18f),V=new(Mathf.Cos(a)*speed,random.RandfRange(.35f,1.1f),Mathf.Sin(a)*speed),Life=random.RandfRange(.16f,.4f),Size=random.RandfRange(.025f,.065f),Color=ev.Kind=="hurt"?Coral:ev.Kind=="boostStart"?Foam:Cream});
        }
    }
    void DrawBurst(Burst b)
    {
        float t=b.Age/b.Life, alpha=1-t;
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
        var color=b.Kind=="slam"?Coral:b.Kind=="explosion"?Cream:Aqua;
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
            if(p.Kind is not (PlaceKind.Fishing or PlaceKind.Treasure or PlaceKind.Wreck)) continue;
            bool casting=v.Mode==VoyageMode.Fishing && v.FishingPlace?.Id==p.Id;
            if(v.World.Depletion.GetValueOrDefault(p.Id)>0 && !casting) continue;
            if(V2.DistanceSquared(v.Position,p.Position)>1800*1800) continue;
            livePlaces.Add(p.Id);
            if(!encounters.TryGetValue(p.Id,out var encounter))
            {
                encounter=new() {Root=new Node3D(),Place=p}; AddChild(encounter.Root); encounters[p.Id]=encounter;
                if(p.Kind==PlaceKind.Treasure) BuildTreasure(encounter.Root);
                else if(p.Kind==PlaceKind.Wreck) BuildWreck(encounter.Root,p.Style);
                else BuildFish(encounter);
            }
            encounter.Root.Position=World(p.Position,p.Kind==PlaceKind.Fishing?.02f:.02f+Mathf.Sin(time*1.9f+p.Style%29)*.018f);
            encounter.Root.Rotation=new(0,p.Kind==PlaceKind.Wreck?.2f:p.Kind==PlaceKind.Treasure?-.15f:0,p.Kind==PlaceKind.Fishing?0:Mathf.Sin(time*1.6f+p.Style%11)*.022f);
            if(p.Kind==PlaceKind.Fishing)
            {
                float phase=p.Style%19;
                for(int i=0;i<encounter.Fish.Count;i++)
                {
                    var node=encounter.Fish[i]; float row=i/2f;
                    node.Position=new((i%2==0?-.18f:.17f)+Mathf.Sin(time*.7f+row+phase)*.075f,.007f,(row-1.35f)*.25f+Mathf.Sin(time*.55f+phase)*.05f);
                    node.Rotation=new(0,-.85f+Mathf.Sin(time*.85f+row)*.12f,0);
                }
            }
        }
        foreach(var id in encounters.Keys.ToArray()) if(!livePlaces.Contains(id)) {encounters[id].Root.QueueFree();encounters.Remove(id);}
    }
    void BuildTreasure(Node3D root)
    {
        EffectsGeometry.Part(root,box,wood,new(0,.15f,0),new(.46f,.28f,.33f));
        // The lid is an arch made from rounded longitudinal slats, with matching metal bands.
        for(int i=0;i<7;i++)
        {
            float angle=-Mathf.Pi*.5f+i*Mathf.Pi/6; var at=new Vector3(0,.285f+Mathf.Cos(angle)*.14f,Mathf.Sin(angle)*.16f);
            EffectsGeometry.Part(root,box,i%3==0?woodDark:wood,at,new(.46f,.055f,.084f),new(angle,0,0));
            foreach(float x in new[]{-.14f,.14f}) EffectsGeometry.Part(root,box,brass,at+new Vector3(x,.012f,0),new(.033f,.026f,.095f),new(angle,0,0));
        }
        foreach(float x in new[]{-.14f,.14f}) foreach(float z in new[]{-.169f,.169f}) EffectsGeometry.Part(root,box,brass,new(x,.16f,z),new(.034f,.25f,.025f));
        EffectsGeometry.Part(root,box,brass,new(0,.21f,.184f),new(.07f,.09f,.03f));
    }
    void BuildWreck(Node3D root,uint style)
    {
        var rng=new SeedRandom(style);
        for(int i=0;i<7;i++)
        {
            float z=(i-3)*.115f; float length=.85f*(1-Mathf.Abs(i-3)*.1f);
            EffectsGeometry.Part(root,box,i%2==0?wood:woodDark,new(rng.Range(-.1f,.08f),.028f,z),new(length,.065f,.093f),new(rng.Range(-.08f,.08f),rng.Range(-.12f,.12f),-.07f));
        }
        for(int i=0;i<5;i++)
        {
            float x=(i-2)*.17f;
            EffectsGeometry.Part(root,box,woodDark,new(x,.11f,-.32f+Mathf.Abs(i-2)*.06f),new(.055f,.22f,.07f),new(-.2f,0,.12f));
            EffectsGeometry.Part(root,box,wood,new(x+.025f,.065f,.32f-Mathf.Abs(i-2)*.05f),new(.06f,.14f,.08f),new(.35f,0,.15f));
        }
        EffectsGeometry.Part(root,box,woodDark,new(.035f,.42f,-.025f),new(.05f,.86f,.055f),new(.06f,0,-.2f));
        // Torn cloth has physical thickness and folds, with an irregular missing corner.
        var cloth=new SurfaceTool(); cloth.Begin(Mesh.PrimitiveType.Triangles);
        Vector3[] vertices=[new(.13f,.8f,-.035f),new(.5f,.45f,.015f),new(.33f,.47f,.055f),new(.34f,.23f,.08f),new(.06f,.32f,-.025f)];
        for(int i=1;i<vertices.Length-1;i++) {cloth.AddVertex(vertices[0]);cloth.AddVertex(vertices[i]);cloth.AddVertex(vertices[i+1]);}
        cloth.GenerateNormals();
        var clothMaterial=EffectsGeometry.Matte("bdbba2");clothMaterial.CullMode=BaseMaterial3D.CullModeEnum.Disabled;
        EffectsGeometry.Part(root,cloth.Commit(),clothMaterial,Vector3.Zero,Vector3.One);
    }
    void BuildFish(Encounter e)
    {
        // Thin, muted water-coloured forms just above the opaque water plane read as submerged schools.
        for(int i=0;i<6;i++)
        {
            var node=new Node3D();e.Root.AddChild(node);e.Fish.Add(node);
            EffectsGeometry.Part(node,sphere,fish,Vector3.Zero,new(.07f,.018f,.24f));
            var tail=new SurfaceTool();tail.Begin(Mesh.PrimitiveType.Triangles);
            tail.AddVertex(new(0,.003f,.075f));tail.AddVertex(new(-.05f,.003f,.15f));tail.AddVertex(new(.05f,.003f,.15f));tail.GenerateNormals();
            var tailMaterial=EffectsGeometry.Matte("457e83");tailMaterial.CullMode=BaseMaterial3D.CullModeEnum.Disabled;
            EffectsGeometry.Part(node,tail.Commit(),tailMaterial,Vector3.Zero,Vector3.One);
            // One restrained upper flank, not an overhead symbol or bright boundary.
            EffectsGeometry.Part(node,sphere,EffectsGeometry.Matte("639393"),new(-.012f,.009f,-.015f),new(.025f,.006f,.14f));
        }
    }
    void DrawEncounters(Voyage v)
    {
        foreach(var e in encounters.Values)
        {
            if(e.Place.Kind==PlaceKind.Fishing) continue;
            var p=World(e.Place.Position,.034f);float radius=e.Place.Kind==PlaceKind.Treasure?.26f:.51f;
            foam.Arc(p,radius,time*.3f+e.Place.Style%13,.95f,.009f,Fade(Foam,.24f));
            foam.Arc(p,radius*1.1f,time*.3f+e.Place.Style%13+3.2f,.65f,.008f,Fade(Foam,.2f));
        }
        foreach(var place in v.World.Places)
        {
            if(place.Kind!=PlaceKind.Current || V2.DistanceSquared(v.Position,place.Position)>1500*1500) continue;
            var center=World(place.Position,.028f);var dir=World(OceanWorld.FlowDirection(place),0)*100;var side=new Vector3(-dir.Z,0,dir.X);
            for(int lane=-1;lane<=1;lane++) for(int i=0;i<4;i++)
            {
                float x=((i*1.21f+time*.65f+lane*.37f)%4.5f)-2.25f;
                var p=center+dir*x+side*(lane*.31f+Mathf.Sin(x*2+lane)*.045f);
                float alpha=(1-Mathf.Abs(x)/2.25f)*.19f;
                // Short tapered moving streaks communicate flow without a diagram of arrows.
                foam.Ribbon(p-dir*.26f,p,.004f,.014f,Fade(Aqua,alpha));
                foam.Ribbon(p,p+dir*.075f,.014f,.001f,Fade(Aqua,alpha));
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
