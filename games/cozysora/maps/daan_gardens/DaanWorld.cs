using Godot;

namespace CozySora;

public partial class DaanWorld : CozyMap
{
    public static readonly Vector2 Pond = new(-31, -17);
    public static readonly Vector2 Island = new(-38, -19);
    public sealed record ParkPath(List<Vector2> Points, float Width);
    private readonly record struct PathSegment(Vector2 A, Vector2 B, float Width);
    private sealed record Bird(Node3D Node, double Phase, Node3D[] Wings);
    public List<ParkPath> Paths { get; } = new();
    private readonly List<PathSegment> _pathSegments = new();
    private readonly Dictionary<Vector2I, List<int>> _pathGrid = new();
    public Node3D StaticContent { get; private set; } = null!;
    private readonly List<Bird> _birds = new(), _flyers = new();
    private double _elapsed;

    public override async Task Build()
    {
        SupportsSurfaceTraversal = true;
        FlightBounds = new(new Vector3(-124, .35f, -111), new Vector3(251, 95, 223));
        Ambience = new()
        {
            ["wind_gain"] = .105,
            ["wave_base"] = .002,
            ["wave_swell"] = .001,
            ["cicada_frequencies"] = new Vector2(3600, 4050),
            ["cicada_gain"] = .001,
            ["birds"] = true
        };
        MakePaths();
        ScenicViews = new()
        {
            ["entrance"] = [58, -57, HeightAt(58, -57), 1, -.03f],
            ["pond"] = [-6, -44, HeightAt(-6, -44) + .3f, 2.39f, -.07f],
            ["deck"] = [-1, -23, 1.32f, 1.65f, -.08f],
            ["cafe_door"] = [98, -58, 1.2f, -1.57f, .01f],
            ["pavilion_seat"] = [-50.5f, 57.5f, HeightAt(-50.5f, 57.5f), .2f, .13f],
            ["habitat"] = [-44, -25, HeightAt(-44, -25), -.78f, -.04f],
            ["island"] = [-48, 10, HeightAt(-48, 10) + .6f, -.33f, -.04f],
            ["banyan"] = [5, 34, HeightAt(5, 34), Mathf.Pi, .08f],
            ["pavilion"] = [-35, 40, HeightAt(-35, 40), 2.33f, -.03f],
            ["grove"] = [-73, 39, HeightAt(-73, 39), 2.5f, -.04f],
            ["lawn"] = [36, 22, HeightAt(36, 22), .1f, -.04f],
            ["cafes"] = [80, -46, 1.2f, -1.57f, -.02f],
            ["lane"] = [92, 12, 1.2f, 3.14f, -.02f],
            ["flight"] = [45, 80, 67, .3f, -.55f],
            ["top"] = [0, 2, 190, 0, -1.57f]
        };
        var atmosphere = GD.Load<CozyAtmosphere>("res://maps/daan_gardens/atmosphere.tres");
        atmosphere.Install(this);
        foreach (Node child in GetChildren())
            if (child is WorldEnvironment environment)
            {
                environment.Environment.SsrEnabled = true;
                environment.Environment.SsrMaxSteps = 48;
            }
        ReportProgress("Opening the park gates…", .08f);
        await NextFrame();
        GenerationSignature = CozySceneCache.Signature("res://maps/daan_gardens");
        string cache = "user://daan_gardens_" + GenerationSignature + ".scn";
        StaticContent = new Node3D { Name = "Daan Gardens" };
        AddChild(StaticContent);
        if (CozySceneCache.RestoreChildren(StaticContent, cache)) GD.Print("Daan Gardens cache restored: ", cache);
        else
        {
            var geometry = new DaanGeometry(StaticContent) { GroundHeight = HeightAt };
            Terrain(geometry);
            Paving(geometry);
            ReportProgress("Opening the café shutters…", .25f);
            await NextFrame();
            new DaanNeighborhood().Build(this, geometry);
            new DaanFurnishings().Build(this, geometry);
            ReportProgress("Spreading the banyan shade…", .5f);
            await NextFrame();
            await new DaanPlanting().Build(this, geometry);
            geometry.Finish();
            CozySceneCache.Save(StaticContent, cache);
            GD.Print("Daan Gardens generated: ", cache);
        }
        BirdLife();
        var air = GD.Load<CozyAirParticles>("res://maps/daan_gardens/air.tres");
        foreach (var at in new Vector2[] { new(5, 42), new(-70, 44), new(47, -45) }) air.Install(this, Point(at.X, at.Y, 3));
        atmosphere.InstallPost(this);
        ReportProgress("A quiet afternoon is waiting.", 1);
    }

    public float PondRadius(float x, float z)
    {
        var p = (new Vector2(x, z) - Pond) / new Vector2(30, 23);
        float angle = Mathf.Atan2(p.Y, p.X);
        return p.Length() / (1 + .065f * Mathf.Sin(angle * 3) + .035f * Mathf.Cos(angle * 5));
    }

    public float IslandRadius(float x, float z)
    {
        var p = (new Vector2(x, z) - Island) / new Vector2(8.3f, 6.4f);
        float angle = Mathf.Atan2(p.Y, p.X);
        return p.Length() / (1 + .11f * Mathf.Sin(angle * 3) + .045f * Mathf.Cos(angle * 7));
    }

    public override float HeightAt(float x, float z)
    {
        float d = PondRadius(x, z);
        if (d < 1.09f)
        {
            float water = Mathf.Lerp(.44f, 1.2f, Mathf.SmoothStep(.97f, 1.09f, d));
            return Mathf.Max(water, Mathf.Lerp(1.18f, .44f, Mathf.SmoothStep(.76f, 1.15f, IslandRadius(x, z))));
        }
        if (x > 70) return 1.2f;
        return 1.2f + .26f * Mathf.Sin(x * .035f) * Mathf.Sin(z * .04f) * Mathf.SmoothStep(1.1f, 1.4f, d);
    }

    public override bool Walkable(float x, float z)
    {
        if (x < -109 || x > 120 || Mathf.Abs(z) > 101) return false;
        if (DeckFootprint(x, z)) return true;
        return PondRadius(x, z) > 1.025f || IslandRadius(x, z) < .98f;
    }

    public bool DeckFootprint(float x, float z, float margin = 0) =>
        (x >= -4.5f - margin && x <= 2.5f + margin && Mathf.Abs(z + 23) <= 3 + margin) ||
        (x >= 2.5f - margin && x <= 8 + margin && Mathf.Abs(z + 23) <= 1.3f + margin);

    public Vector3 Point(float x, float z, float lift = 0) => new(x, HeightAt(x, z) + lift, z);

    private void Curve(IReadOnlyList<Vector2> points, bool closed, float width)
    {
        List<Vector2> curve = new();
        int count = points.Count;
        for (int i = 0; i < (closed ? count : count - 1); i++)
        {
            var p0 = points[closed ? (i - 1 + count) % count : Math.Max(0, i - 1)];
            var p1 = points[i];
            var p2 = points[(i + 1) % count];
            var p3 = points[closed ? (i + 2) % count : Math.Min(count - 1, i + 2)];
            for (int j = 0; j < 16; j++)
            {
                float t = j / 16f;
                curve.Add(.5f * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t +
                    (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t));
            }
        }
        curve.Add(closed ? curve[0] : points[^1]);
        Paths.Add(new(curve, width));
        for (int i = 0; i < curve.Count - 1; i++)
        {
            var a = curve[i];
            var b = curve[i + 1];
            int id = _pathSegments.Count;
            _pathSegments.Add(new(a, b, width));
            for (int ix = Mathf.FloorToInt((Mathf.Min(a.X, b.X) - width) / 8); ix <= Mathf.FloorToInt((Mathf.Max(a.X, b.X) + width) / 8); ix++)
                for (int iz = Mathf.FloorToInt((Mathf.Min(a.Y, b.Y) - width) / 8); iz <= Mathf.FloorToInt((Mathf.Max(a.Y, b.Y) + width) / 8); iz++)
                {
                    var key = new Vector2I(ix, iz);
                    if (!_pathGrid.TryGetValue(key, out var ids)) _pathGrid.Add(key, ids = new());
                    ids.Add(id);
                }
        }
    }

    private void MakePaths()
    {
        Curve([new(62, -62), new(26, -76), new(-36, -71), new(-79, -49), new(-83, 6), new(-76, 48),
            new(-52, 77), new(3, 78), new(43, 61), new(63, 26), new(63, -24)], true, 4.8f);
        List<Vector2> ring = new();
        for (int i = 0; i < 12; i++) ring.Add(Pond + new Vector2(Mathf.Cos(i * Mathf.Tau / 12) * 40, Mathf.Sin(i * Mathf.Tau / 12) * 32));
        Curve(ring, true, 3.6f);
        Curve([new(88, -60), new(64, -60), new(37, -45), new(17, -24), new(15, 5), new(5, 38), new(-12, 54), new(-52, 56)], false, 4.4f);
        Curve([new(-83, 20), new(-48, 18), new(-4, 17), new(35, 19), new(63, 28), new(88, 30)], false, 3.8f);
        Curve([new(-75, -45), new(-62, -51), new(-36, -49)], false, 2.2f);
        Curve([new(-72, 42), new(-59, 39), new(-45, 47), new(-52, 56)], false, 2.1f);
        Curve([new(7, 44), new(27, 49), new(45, 62)], false, 2);
    }

    public float PathDistance(float x, float z)
    {
        var p = new Vector2(x, z);
        float best = 99;
        if (!_pathGrid.TryGetValue(new Vector2I(Mathf.FloorToInt(x / 8), Mathf.FloorToInt(z / 8)), out var ids)) return best;
        foreach (int id in ids)
        {
            var segment = _pathSegments[id];
            var v = segment.B - segment.A;
            best = Mathf.Min(best, p.DistanceTo(segment.A + v * Mathf.Clamp((p - segment.A).Dot(v) / v.LengthSquared(), 0, 1)) - segment.Width * .5f);
        }
        return best;
    }

    public bool PlantedClear(float x, float z, float margin = 0)
    {
        if (DeckFootprint(x, z, margin + .3f) || x > 72 || Mathf.Abs(z) > 94 || x < -103) return false;
        if (PathDistance(x, z) < margin || PondRadius(x, z) < 1.12f) return false;
        foreach (var plaza in new Vector3[] { new(5, 42, 11.5f), new(-52, 56, 9.5f), new(62, -60, 9) })
            if (new Vector2(x - plaza.X, z - plaza.Y).Length() < plaza.Z + margin) return false;
        return true;
    }

    private void Terrain(DaanGeometry geometry)
    {
        geometry.Box(new(0, .1f, 0), new(2400, .1f, 2400), "8c9b8b");
        var surface = new SurfaceTool();
        surface.Begin(Mesh.PrimitiveType.Triangles);
        for (int iz = 0; iz < 260; iz++)
            for (int ix = 0; ix < 300; ix++)
            {
                float x = ix - 145;
                float z = iz - 130;
                foreach (var at in new[] { Point(x, z), Point(x + 1, z), Point(x + 1, z + 1), Point(x, z), Point(x + 1, z + 1), Point(x, z + 1) })
                    surface.AddVertex(at);
            }
        surface.GenerateNormals();
        var terrain = geometry.Mesh(surface.Commit(), "7c9252", true);
        terrain.MaterialOverride = new ShaderMaterial { Shader = GD.Load<Shader>("res://maps/daan_gardens/ground.gdshader") };
        var water = new SurfaceTool();
        water.Begin(Mesh.PrimitiveType.Triangles);
        for (int i = 0; i < 128; i++)
        {
            water.AddVertex(new(Pond.X, .51f, Pond.Y));
            foreach (float angle in new[] { i * Mathf.Tau / 128, (i + 1) * Mathf.Tau / 128 })
            {
                float r = 1 + .065f * Mathf.Sin(angle * 3) + .035f * Mathf.Cos(angle * 5);
                water.AddVertex(new(Pond.X + Mathf.Cos(angle) * 30 * r, .51f, Pond.Y + Mathf.Sin(angle) * 23 * r));
            }
        }
        water.GenerateNormals();
        CozyPrimitives.Instance(StaticContent, water.Commit(), Vector3.Zero,
            new ShaderMaterial { Shader = GD.Load<Shader>("res://maps/daan_gardens/pond.gdshader") });
    }

    private void Paving(DaanGeometry geometry)
    {
        foreach (var path in Paths)
        {
            var points = path.Points.Select(p => Point(p.X, p.Y, .04f)).ToArray();
            geometry.Ribbon(points, path.Width + .3f, "a6a58e", 0);
            for (int i = 0; i < points.Length; i++) points[i].Y += .008f;
            geometry.Ribbon(points, path.Width, "bfb9a2");
        }
        foreach (var at in new Vector2[] { new(5, 42), new(-52, 56), new(62, -60) })
            geometry.Disc(Point(at.X, at.Y, .065f), at.X == 5 ? 11 : 9, "b6ae96");
        geometry.Box(new(85.5f, 1.23f, 0), new(11, .06f, 290), "646b65");
        geometry.Box(new(76.8f, 1.23f, 0), new(6.4f, .06f, 290), "bcb7a3", false, 0, 1);
        geometry.Box(new(95.1f, 1.23f, 0), new(8.2f, .06f, 290), "b6b5a4", false, 0, 1);
        foreach (float z in new[] { -121f, 121f })
        {
            geometry.Box(new(14, 1.23f, z), new(290, .06f, 10), "646b65");
            foreach (int side in new[] { -1, 1 }) geometry.Box(new(14, 1.23f, z + side * 6.5f), new(290, .06f, 3), "b6b5a4", false, 0, 1);
        }
        for (int z = -137; z < 140; z += 8) geometry.Box(new(85.5f, 1.27f, z), new(.12f, .02f, 3.5f), "d1be75");
        foreach (int z in new[] { -60, 30 })
            for (int x = 81; x < 91; x += 2) geometry.Box(new(x, 1.28f, z), new(1.1f, .025f, 3.5f), "e8dfc1");
    }

    private void BirdLife()
    {
        var palette = new CozySolidMaterials();
        for (int i = 0; i < 4; i++)
        {
            var bird = new Node3D();
            AddChild(bird);
            CozyPrimitives.Sphere(bird, Vector3.Zero, new(.12f, .13f, .32f), palette.Color("ece8d3"));
            CozyPrimitives.Sphere(bird, new(0, .09f, .34f), new(.075f, .07f, .08f), palette.Color("ece8d3"));
            CozyPrimitives.Beam(bird, new(0, .06f, .18f), new(0, .09f, .34f), .04f, palette.Color("ece8d3"));
            CozyPrimitives.Beam(bird, new(0, .09f, .38f), new(0, .085f, .53f), .018f, palette.Color("77816b"));
            List<Node3D> wings = new();
            foreach (int side in new[] { -1, 1 })
            {
                var wing = new Node3D();
                bird.AddChild(wing);
                CozyPrimitives.Sphere(wing, new(side * .36f, 0, -.04f), new(.46f, .035f, .19f), palette.Color("eee9d4"));
                CozyPrimitives.Sphere(wing, new(side * .65f, 0, -.14f), new(.24f, .022f, .13f), palette.Color("d3d8c5"));
                wings.Add(wing);
            }
            _flyers.Add(new(bird, i * 1.73, wings.ToArray()));
        }
        for (int i = 0; i < 16; i++)
        {
            var bird = new Node3D();
            AddChild(bird);
            CozyPrimitives.Sphere(bird, new(0, .14f, 0), new(.13f, .2f, .28f), palette.Color("efe9d6"));
            CozyPrimitives.Beam(bird, new(0, .22f, -.08f), new(0, .55f, .07f), .04f, palette.Color("efe9d6"));
            CozyPrimitives.Sphere(bird, new(0, .57f, .08f), new(.065f, .065f, .07f), palette.Color("eee8d7"));
            CozyPrimitives.Beam(bird, new(0, .57f, .1f), new(0, .55f, .28f), .02f, palette.Color("4c5953"));
            foreach (int side in new[] { -1, 1 })
                CozyPrimitives.Beam(bird, new(side * .045f, 0, 0), new(side * .045f, .18f, 0), .012f, palette.Color("59604e"));
            float angle = i * 2.399f;
            float radius = .35f + .6f * (float)(i * .618 % 1);
            var p = Island + new Vector2(Mathf.Cos(angle), Mathf.Sin(angle)) * new Vector2(7.5f, 5.8f) * radius;
            bird.Position = Point(p.X, p.Y);
            _birds.Add(new(bird, angle, []));
        }
    }

    public override void _Process(double delta)
    {
        _elapsed += delta;
        foreach (var bird in _flyers)
        {
            double a = _elapsed * .085 + bird.Phase;
            bird.Node.Position = new(Pond.X + (float)Math.Cos(a) * 27, 6 + (float)Math.Sin(a * 1.8 + bird.Phase) * 1.4f, Pond.Y + (float)Math.Sin(a) * 22);
            bird.Node.Rotation = new(0, (float)Math.Atan2(-Math.Sin(a) * 27, Math.Cos(a) * 22), (float)Math.Sin(a) * .10f);
            for (int i = 0; i < 2; i++) bird.Wings[i].Rotation = new(0, 0, (i == 0 ? 1 : -1) * (float)Math.Sin(_elapsed * 3.2 + bird.Phase) * .3f);
        }
        foreach (var bird in _birds) bird.Node.Rotation = new(0, (float)(bird.Phase + Math.Sin(_elapsed * .22 + bird.Phase) * .35), 0);
    }
}
