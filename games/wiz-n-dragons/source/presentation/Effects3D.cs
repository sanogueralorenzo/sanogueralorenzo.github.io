using Godot;
using WizNDragons.Core;
using V2 = System.Numerics.Vector2;
namespace WizNDragons;

// Presentation only. Samples actual simulation positions; never advances or changes the flight.
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
    Mesh sphere = null!;
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
    sealed class Encounter { public Node3D Root = null!; public Place Place = null!; }
    static Vector3 World(V2 p, float height = .035f) => new(p.X * .01f, height, p.Y * .01f);
    static Color Fade(Color color, float alpha) => new(color, Mathf.Clamp(alpha, 0, 1));

    void EnsureReady()
    {
        if (initialized) return;
        initialized = true; foam = new(this, true); solid = new(this, false);
        sphere = new SphereMesh { Radius = .5f, Height = 1, RadialSegments = 12, Rings = 6 };
        balls = new MultiMesh { TransformFormat = MultiMesh.TransformFormatEnum.Transform3D, UseColors = true, Mesh = sphere, InstanceCount = 1024, VisibleInstanceCount = 0 };
        AddChild(new MultiMeshInstance3D { Multimesh = balls, MaterialOverride = new StandardMaterial3D { VertexColorUseAsAlbedo = true, VertexColorIsSrgb = true, Roughness = .82f }, CastShadow = GeometryInstance3D.ShadowCastingSetting.Off });
    }
    public void Reset()
    {
        wake.Clear(); trails.Clear(); creatureWakes.Clear(); bursts.Clear(); sparks.Clear();
        foreach (var e in encounters.Values) e.Root.QueueFree(); encounters.Clear();
        time = sampleClock = 0; Destination = null;
        if (initialized) { foam.Begin(); foam.End(); solid.Begin(); solid.End(); balls.VisibleInstanceCount = 0; }
    }
    public void Sync(Flight flight, float clock, float dt)
    {
        EnsureReady();
        // Use flight time for transient effects so menus pause them.
        bool active = flight.IsActive;
        float step = active ? Mathf.Clamp(dt, 0, .1f) : 0;
        time += step;
        if (step > 0)
        {
            foreach (var p in sparks) { p.Age += step; p.P += p.V * step; p.V *= MathF.Exp(-step * 2); p.V.Y -= step * 2.4f; }
            sparks.RemoveAll(p => p.Age >= p.Life);
            foreach (var b in bursts) b.Age += step;
            bursts.RemoveAll(b => b.Age >= b.Life);
            SampleTrails(flight, step);
        }
        SyncEncounters(flight);
        foam.Begin(); solid.Begin(); ballCount = 0;
        DrawWake(wake, .34f, 1.9f, 1);
        DrawWard(flight);
        foreach (var enemy in flight.Enemies)
        {
            if (enemy.Health <= 0) continue;
            if (creatureWakes.TryGetValue(enemy.Id, out var history)) DrawWake(history, enemy.Radius * .006f, .85f, .38f);
            DrawEmergence(enemy);
        }
        foreach (var shot in flight.Shots) if (shot.Life > 0) DrawShot(shot);
        foreach (var b in bursts) DrawBurst(b);
        foreach (var p in sparks) Ball(p.P, Vector3.One * p.Size * (1 - p.Age / p.Life), p.Color);
        DrawEncounters(flight);
        if (Destination is V2 destination)
        {
            var p = World(destination, .05f);
            foam.Arc(p, .12f, -.4f, 2.1f, .012f, Fade(Cream,.55f),10);
            foam.Arc(p, .12f, 2.8f, 1.9f, .012f, Fade(Cream,.55f),10);
        }
        foam.End(); solid.End(); balls.VisibleInstanceCount = ballCount;
    }
    void SampleTrails(Flight v, float dt)
    {
        wake.RemoveAll(s => time - s.Born > 2.15f);
        liveShots.Clear(); foreach (var s in v.Shots) if (!s.Hostile && s.Kind == SpellKind.Arcane && s.Life > 0) liveShots.Add(s);
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
    void DrawWake(List<Sample> history,float width,float life,float strength)
    {
        for(int i=1;i<history.Count;i++)
        {
            float fade=Mathf.Clamp(1-(time-history[i].Born)/life,0,1)*strength;
            foam.Ribbon(history[i-1].P,history[i].P,.025f*fade,.04f*fade,Fade(Magic,fade*.65f));
            if(i%5==0) Ball(history[i].P+Vector3.Up*.1f,Vector3.One*.06f*fade,Magic);
        }
    }
    void DrawShot(Shot s)
    {
        var p = World(s.Position, s.Kind == SpellKind.Rune ? .1f : .24f);
        var dir = World(SkyWorld.Unit(s.Velocity),0)*100;
        if (s.Hostile)
        {
            float flight = Mathf.Clamp(s.Age / s.FlightDuration, 0, 1);
            p.Y = .12f + .4f * (1 - flight) + Mathf.Sin(flight * Mathf.Pi) * 1.8f;
            Ball(p, Vector3.One * .27f, new("733b3c"));
            Ball(p + new Vector3(-.025f, .07f, -.025f), Vector3.One * .20f, Coral);
            Ball(p + Vector3.Up * .17f, Vector3.One * .055f, Cream);
            return;
        }
        if (s.Kind == SpellKind.Arcane)
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
        else if (s.Kind == SpellKind.Rune)
        {
            Ball(p,Vector3.One*.25f,new("8055a0"));
            for (int i=0;i<4;i++) { float a=i*Mathf.Pi*.5f; Ball(p+new Vector3(Mathf.Cos(a),0,Mathf.Sin(a))*.14f,Vector3.One*.062f,Magic); }
            Ball(p+Vector3.Up*.12f,Vector3.One*.065f,s.Age>=.5f?Coral:Cream);
        }
        else if (s.Kind == SpellKind.Fireball)
        {
            Ball(p,Vector3.One*.12f,new("dc865d")); Ball(p+new Vector3(-.022f,.033f,-.017f),Vector3.One*.045f,new("ffe0a3"));
            foam.Ribbon(p-dir*.25f,p-dir*.06f,.01f,.016f,Fade(Cream,.2f));
        }
        else if (s.Kind == SpellKind.Tether)
        {
            var side=new Vector3(-dir.Z,0,dir.X); solid.Ribbon(p-dir*.29f,p,.019f,.026f,Magic);
            solid.Triangle(p+dir*.075f,p-dir*.09f+side*.065f,p-dir*.06f-side*.065f,Cream);
        }
    }
    void DrawWard(Flight v)
    {
        if (v.Spells[(int)SpellKind.Aura] <= 0) return;
        var center = World(v.Position, .046f); float radius = v.WardRadius * .01f;
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
        if (ev.Kind == "potion" && bursts.Count < 192)
            bursts.Add(new() { Kind = "potion", P = World(ev.Position, .06f), Life = .55f });
        if(ev.Kind is "arc" or "pull" or "aura" or "bulwark" or "explosion" or "calm" or "sparkExplosion" or "bossExplosion")
        {
            if(bursts.Count<192) bursts.Add(new() {Kind=ev.Kind,P=World(ev.Position,ev.Kind is "arc" or "pull"?.3f:.05f),End=World(ev.End,.3f),Life=ev.Kind is "arc" or "pull"?.2f:ev.Kind=="calm"?1.3f:ev.Kind is "sparkExplosion" or "bossExplosion"?.6f:.48f,Size=ev.Value*.01f});
        }
        int count=ev.Kind switch {"hit"=>2,"kill"=>7,"explosion"=>15,"hurt"=>5,"shot"=>3,"ricochet"=>4,"potion"=>3,"heal" or "crystal" or "silver"=>6,"boostStart"=>9,_=>0};
        for(int i=0;i<count && sparks.Count<512;i++)
        {
            float a=random.RandfRange(0,Mathf.Tau), speed=random.RandfRange(.25f,ev.Kind=="explosion"?2.5f:1.2f);
            sparks.Add(new() {P=World(ev.Position,.18f),V=new(Mathf.Cos(a)*speed,random.RandfRange(.35f,1.1f),Mathf.Sin(a)*speed),Life=random.RandfRange(.16f,.4f),Size=random.RandfRange(.025f,.065f),Color=ev.Kind=="hurt"?Coral:ev.Kind=="boostStart"?Foam:Cream});
        }
    }
    void DrawBurst(Burst b)
    {
        float t=b.Age/b.Life, alpha=1-t;
        if (b.Kind == "potion")
        {
            for (int i = 0; i < 6; i++)
            {
                float angle = i * Mathf.Tau / 6 + .3f;
                var direction = new Vector3(Mathf.Cos(angle), 0, Mathf.Sin(angle));
                var p = b.P + direction * (.15f + t * .42f) + Vector3.Up * Mathf.Sin(t * Mathf.Pi) * .25f;
                var edge = new Vector3(-direction.Z, .6f, direction.X) * .04f * alpha;
                var tip = direction * .11f * alpha;
                solid.Triangle(p - edge - tip, p + edge - tip, p + edge + tip, Aqua);
                solid.Triangle(p - edge - tip, p + edge + tip, p - edge + tip, Aqua);
            }
            foam.Arc(b.P, .28f + t * .48f, .3f, 4.8f, .02f, Fade(Foam, alpha * .45f));
            return;
        }
        if (b.Kind is "sparkExplosion" or "bossExplosion")
        {
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

    void SyncEncounters(Flight v)
    {
        livePlaces.Clear();
        foreach(var p in v.World.Places)
        {
            if(p.Kind is not (PlaceKind.Crystal or PlaceKind.Potion)) continue;
            if(v.World.Depletion.GetValueOrDefault(p.Id)>0) continue;
            if(V2.DistanceSquared(v.Position,p.Position)>1800*1800) continue;
            livePlaces.Add(p.Id);
            if(!encounters.TryGetValue(p.Id,out var encounter))
            {
                encounter=new() {Root=new Node3D(),Place=p}; AddChild(encounter.Root); encounters[p.Id]=encounter;
                var art = new ActorGeometry();
                if(p.Kind==PlaceKind.Crystal) art.Crystal(new(0,.25f,0),new(.2f,.4f,.2f),Aqua);
                else
                {
                    art.Sphere(new(0,.15f,0),new(.18f,.22f,.18f),new Color("64c9b9"));
                    art.RoundBox(new(0,.36f,0),new(.12f,.14f,.12f),.02f,new Color("d6b477"));
                    art.RoundBox(new(0,.21f,-.17f),new(.20f,.055f,.025f),.01f,Cream);
                    art.RoundBox(new(0,.21f,-.17f),new(.055f,.20f,.025f),.01f,Cream);
                }
                encounter.Root.AddChild(new MeshInstance3D { Mesh=art.Mesh(DioramaSurface.Material) });
            }
            encounter.Root.Position=World(p.Position,.15f+Mathf.Sin(time*1.9f+p.Style%29)*.08f);
            encounter.Root.Rotation=p.Kind==PlaceKind.Potion
                ? new(.08f, p.Style % 360 * Mathf.Pi / 180, Mathf.Sin(time*1.6f+p.Style%11)*.045f)
                : new(0, p.Kind==PlaceKind.Crystal?p.Heading:0, 0);
        }
        foreach(var id in encounters.Keys.ToArray()) if(!livePlaces.Contains(id)) {encounters[id].Root.QueueFree();encounters.Remove(id);}
    }
    void DrawEncounters(Flight v)
    {
        foreach(var e in encounters.Values)
        {
            if (e.Place.Kind==PlaceKind.Crystal)
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
            var center=World(place.Position,.028f);var dir=World(SkyWorld.FlowDirection(place),0)*100;var side=new Vector3(-dir.Z,0,dir.X);
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
    }
}
