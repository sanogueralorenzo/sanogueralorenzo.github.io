using Godot;

namespace CozySora;

/// <summary>Deterministic coastal terrain, roads and shared ground queries.</summary>
public partial class SeabreezeWorld : CozyMap
{
    public List<List<Vector2>> Roads { get; private set; } = new();
    public List<Vector2> RailPoints { get; private set; } = new();
    public CozySolidMaterials Palette { get; } = new();
    private readonly List<RoadSegment> _segments = new();
    private readonly Dictionary<Vector2I, List<int>> _roadGrid = new();
    private readonly record struct RoadSegment(Vector2 A, Vector2 B, float Length, double Along, int Road);
    public readonly record struct RoadSample(float D, double S, float Tx, float Tz, float Side, int Road);
    public static readonly Dictionary<string, Rect2> Zones = new()
    {
        ["paddy"] = new(63, -8, 39, 52),
        ["paddy_in"] = new(42, 0, 10, 30),
        ["farm"] = new(28, 42, 36, 34),
        ["yard"] = new(36, 50, 18, 14),
        ["village"] = new(-36, 56, 50, 32),
        ["street"] = new(-34, 71, 46, 8),
        ["vending"] = new(-74, 8, 18, 34),
        ["pave"] = new(-70, 12, 10, 26),
        ["gully"] = new(10, 88, 36, 18),
        ["bed"] = new(14, 91, 30, 10)
    };
    private static readonly (string Zone, double Height)[] FlatZones = [("paddy", .4), ("paddy_in", .4), ("farm", 2.6), ("village", 3)];
    private static readonly (string Zone, float Margin)[] ExcludedZones = [("paddy", 1), ("paddy_in", 1), ("yard", 1), ("street", 4), ("pave", 2), ("gully", 2)];

    public override async Task Build()
    {
        GenerationSignature = CozySceneCache.Signature("res://maps/seabreeze_village");
        ScenicViews = new()
        {
            ["coast"] = [-8, -9.3f, 1.05f, -1.2f, -.06f],
            ["paddy"] = [55.2f, -2.6f, .25f, -2.31f, .29f],
            ["farm"] = [53.6f, 60.2f, 3, 2.98f, .1f],
            ["rail"] = [19.2f, 80, 2.7f, -3.02f, .41f],
            ["village"] = [-4.6f, 74.7f, 2.55f, 1.32f, 0],
            ["alley"] = [-26.4f, 77.9f, 2.65f, 3.55f, .2f],
            ["vending"] = [-61.65f, 26.2f, 1.22f, 1.571f, .16f],
            ["viaduct"] = [-64.3f, 58.6f, 2.9f, -1.95f, .52f],
            ["shrine"] = [-.7f, 8, 5.7f, -3.16f, .48f],
            ["top"] = [0, 30, 140, 0, -1.5f]
        };
        Ambience = new() { ["wind_gain"] = .12, ["wave_base"] = .022, ["wave_swell"] = .018, ["cicada_frequencies"] = new Vector2(3820, 4075), ["cicada_gain"] = .0018, ["birds"] = true };
        ReportProgress("Tracing the coastal lanes…", .08f);
        await NextFrame();
        BuildRoads();
        var atmosphere = GD.Load<CozyAtmosphere>("res://maps/seabreeze_village/atmosphere.tres");
        atmosphere.Install(this);
        ReportProgress("Shaping fields and shoreline…", .14f);
        await NextFrame();
        await BuildTerrain();
        BuildCoastProps();
        ReportProgress("Opening the village…", .38f);
        await NextFrame();
        var settlement = new SeabreezeSettlements();
        AddChild(settlement);
        await settlement.Build(this);
        ReportProgress("Growing the summer gardens…", .60f);
        await NextFrame();
        var vegetation = new SeabreezeVegetation();
        AddChild(vegetation);
        await vegetation.Build(this);
        var life = new SeabreezeSummerLife();
        AddChild(life);
        life.Build(this);
        atmosphere.InstallPost(this);
        ReportProgress("The coast is ready.", .98f);
    }

    public static float Curve(float x) => (float)CurveValue(x);
    private static double CurveValue(double x) => -.0022 * x * x + .00001 * x * x * x;
    public static double Smooth(double a, double b, double value)
    {
        double t = Math.Clamp((value - a) / (b - a), 0, 1);
        return t * t * (3 - 2 * t);
    }
    // The sine hash needs double precision: rounding before the large multiplier
    // changes the terrain noise and therefore the entire seeded plant distribution.
    public static double Hash2(double x, double z)
    {
        double value = Math.Sin(x * 127.1 + z * 311.7) * 43758.5453;
        return value - Math.Floor(value);
    }
    public static double Noise2(double x, double z)
    {
        double ix = Math.Floor(x), iz = Math.Floor(z);
        double fx = Smooth(0, 1, x - ix), fz = Smooth(0, 1, z - iz);
        return Lerp(Lerp(Hash2(ix, iz), Hash2(ix + 1, iz), fx), Lerp(Hash2(ix, iz + 1), Hash2(ix + 1, iz + 1), fx), fz);
    }
    private static double Lerp(double a, double b, double t) => a + (b - a) * t;

    public static List<Vector2> Spline(IReadOnlyList<Vector2> points, bool closed, int subdivisions)
    {
        var result = new List<Vector2>();
        int count = points.Count;
        for (int i = 0; i < (closed ? count : count - 1); i++)
        {
            var p0 = points[closed ? Mathf.PosMod(i - 1, count) : Math.Max(0, i - 1)];
            var p1 = points[i]; var p2 = points[(i + 1) % count];
            var p3 = points[closed ? (i + 2) % count : Math.Min(count - 1, i + 2)];
            for (int j = 0; j < subdivisions; j++)
            {
                float t = (float)j / subdivisions;
                result.Add(.5f * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t));
            }
        }
        if (!closed) result.Add(points[^1]);
        return result;
    }

    private void BuildRoads()
    {
        var loop = new List<Vector2>();
        for (int x = -38; x < 39; x += 4) loop.Add(new(x, (float)(-12.5 + CurveValue(x))));
        loop.AddRange([new(50, -8), new(56, 4), new(57, 20), new(55, 36), new(50, 50), new(40, 60), new(26, 66), new(10, 68), new(-10, 68), new(-26, 66), new(-40, 60), new(-50, 50), new(-55, 36), new(-57, 20), new(-56, 4), new(-50, -8)]);
        var coast = new List<Vector2>();
        for (int x = -100; x < 131; x += 5) coast.Add(new(x, (float)(-12.5 + CurveValue(x))));
        Roads = [Spline(loop, true, 6), Spline(coast, false, 4)];
        for (int ri = 0; ri < Roads.Count; ri++)
        {
            var points = Roads[ri];
            double along = 0;
            for (int i = 0; i < (ri == 0 ? points.Count : points.Count - 1); i++)
            {
                var a = points[i]; var b = points[(i + 1) % points.Count];
                float length = a.DistanceTo(b);
                int id = _segments.Count;
                _segments.Add(new(a, b, length, along, ri));
                along += length;
                for (int z = Mathf.FloorToInt((Mathf.Min(a.Y, b.Y) - 14) / 8); z <= Mathf.FloorToInt((Mathf.Max(a.Y, b.Y) + 14) / 8); z++)
                    for (int x = Mathf.FloorToInt((Mathf.Min(a.X, b.X) - 14) / 8); x <= Mathf.FloorToInt((Mathf.Max(a.X, b.X) + 14) / 8); x++)
                    {
                        var key = new Vector2I(x, z);
                        if (!_roadGrid.TryGetValue(key, out var ids)) _roadGrid.Add(key, ids = new());
                        ids.Add(id);
                    }
            }
        }
        RailPoints = Spline([new(-80, 36), new(-52, 54), new(-44, 68), new(-40, 84), new(-20, 96), new(60, 96), new(108, 70)], false, 8);
    }

    public RoadSample RoadInfo(float x, float z)
    {
        var point = new Vector2(x, z);
        float best = 9801, tx = 1, tz = 0, side = 1;
        double along = 0;
        int road = -1;
        if (_roadGrid.TryGetValue(new(Mathf.FloorToInt(x / 8), Mathf.FloorToInt(z / 8)), out var ids))
            foreach (int id in ids)
            {
                var segment = _segments[id]; var v = segment.B - segment.A;
                float t = Mathf.Clamp((point - segment.A).Dot(v) / v.LengthSquared(), 0, 1);
                var delta = point - (segment.A + v * t);
                float distance = delta.LengthSquared();
                if (distance >= best) continue;
                best = distance;
                along = segment.Along + t * segment.Length;
                tx = v.X / segment.Length; tz = v.Y / segment.Length;
                side = v.Cross(delta) >= 0 ? 1 : -1;
                road = segment.Road;
            }
        return new(Mathf.Sqrt(best), along, tx, tz, side, road);
    }

    public float RailDistance(float x, float z)
    {
        float best = 1000000;
        var point = new Vector2(x, z);
        for (int i = 0; i < RailPoints.Count - 1; i++)
        {
            var a = RailPoints[i]; var v = RailPoints[i + 1] - a;
            best = Mathf.Min(best, (point - a - v * Mathf.Clamp((point - a).Dot(v) / v.LengthSquared(), 0, 1)).LengthSquared());
        }
        return Mathf.Sqrt(best);
    }

    public static double ZoneWeight(Rect2 zone, double x, double z, double margin)
    {
        var distance = new Vector2((float)Math.Max(Math.Max(zone.Position.X - x, x - zone.End.X), 0), (float)Math.Max(Math.Max(zone.Position.Y - z, z - zone.End.Y), 0));
        return 1 - Smooth(0, margin, distance.Length());
    }
    public static float RoadHeight(float x, float z) => (float)Math.Clamp(.045 * (z + 12), 0, 3);
    public override float HeightAt(float x, float z) => (float)GroundHeight(x, z);
    private double GroundHeight(double x, double z)
    {
        double relative = z - CurveValue(x);
        double rough = (Noise2(x * .08 + 3.1, z * .08 + 7.7) - .5) * 1.4 + (Noise2(x * .35, z * .35) - .5) * .25;
        double roadHeight = Math.Clamp(.045 * (z + 12), 0, 3);
        double h = roadHeight + rough;
        h += Smooth(-74, -125, x) * 20 * (1 + .25 * Noise2(x * .03, z * .03));
        h += Smooth(88, 135, z) * 25 * (1 + .25 * Noise2(x * .03 + 5, z * .03));
        h += Smooth(104, 145, x) * 12 * (1 + .25 * Noise2(x * .03 + 9, z * .03 + 2));
        float radius = new Vector2((float)x, (float)(z - 30)).Length();
        h += 8 * (1 - Smooth(8, 27, radius)) * (1 + .08 * Noise2(x * .2, z * .2));
        if (radius < 8) h -= rough * .8;
        foreach (var (zone, height) in FlatZones) h = Lerp(h, height, ZoneWeight(Zones[zone], x, z, 6));
        h = Lerp(h, roadHeight, ZoneWeight(Zones["vending"], x, z, 6));
        h -= 5.5 * ZoneWeight(Zones["bed"], x, z, 7) * (1 - .3 * Noise2(x * .3, z * .3));
        h = Lerp(h, roadHeight, 1 - Smooth(4.6, 9.5, RoadInfo((float)x, (float)z).D));
        double lay = Smooth(-12, -8, x) * (1 - Smooth(-4.8, .2, x)) * (1 - Smooth(6, 11, relative)) * Smooth(-11.5, -8.5, relative);
        h = Lerp(h, 0, lay) + lay * (Noise2(x * .6, z * .6) - .5) * .12;
        if (z < -4) h = Lerp(h, -34, Smooth(17, 26, -relative));
        return Math.Max(h, -34);
    }
    public override bool Walkable(float x, float z) => Mathf.Abs(x) <= 118 && z <= 100 && z >= -40 && !(z < -4 && z - CurveValue(x) < -19.2) && HeightAt(x, z) >= -1.5f;
    public bool Excluded(float x, float z, float margin = 1.5f)
    {
        if (RoadInfo(x, z).D < 4 + margin) return true;
        foreach (var (zone, padding) in ExcludedZones) if (Zones[zone].Grow(padding).HasPoint(new(x, z))) return true;
        return z > 30 && RailDistance(x, z) < 4 || new Vector2(x, z - 30).Length() < 8 || x > -11 && x < 11 && z > 5 && z < 23;
    }

    private async Task BuildTerrain()
    {
        string terrainPath = "user://terrain_" + GenerationSignature + ".res", layoutPath = "user://layout_" + GenerationSignature + ".res";
        if (Godot.FileAccess.FileExists(terrainPath) && Godot.FileAccess.FileExists(layoutPath))
        {
            InstallTerrain(GD.Load<ArrayMesh>(terrainPath), GD.Load<Texture2D>(layoutPath));
            return;
        }
        var image = Image.CreateEmpty(1024, 1024, false, Image.Format.Rgba8);
        for (int j = 0; j < 1024; j++)
        {
            if (j % 64 == 0) { ReportProgress("Shaping fields and shoreline…", .14f + .12f * j / 1024); await NextFrame(); }
            float z = -180 + (j + .5f) * 360 / 1024;
            for (int i = 0; i < 1024; i++)
            {
                float x = -180 + (i + .5f) * 360 / 1024;
                var road = RoadInfo(x, z); var point = new Vector2(x, z);
                float zone = 0;
                if (Zones["paddy"].HasPoint(point) || Zones["paddy_in"].HasPoint(point)) zone = .2f;
                else if (Zones["street"].HasPoint(point) || Zones["pave"].HasPoint(point)) zone = .4f;
                else if (Zones["yard"].HasPoint(point)) zone = .6f;
                else if (Zones["bed"].HasPoint(point) || z > 40 && z < 110 && x > -90 && x < 120 && RailDistance(x, z) < 3.5f) zone = .8f;
                image.SetPixel(i, j, new Color(Mathf.Min(road.D, 16) / 16, (float)(road.S % 8) / 8, zone, 1));
            }
        }
        var layout = ImageTexture.CreateFromImage(image);
        ResourceSaver.Save(layout, layoutPath);
        const int n = 440;
        var vertices = new Vector3[(n + 1) * (n + 1)]; var normals = new Vector3[vertices.Length]; var uv = new Vector2[vertices.Length];
        for (int j = 0; j <= n; j++)
            for (int i = 0; i <= n; i++)
            {
                double x = -180.0 + 360.0 * i / n, z = -180.0 + 360.0 * j / n;
                int index = j * (n + 1) + i;
                vertices[index] = new((float)x, (float)GroundHeight(x, z), (float)z);
                normals[index] = Vector3.Up;
                uv[index] = new((float)((x + 180) / 360), (float)((z + 180) / 360));
            }
        for (int j = 1; j < n; j++)
            for (int i = 1; i < n; i++)
            {
                int k = j * (n + 1) + i;
                normals[k] = new Vector3(vertices[k - 1].Y - vertices[k + 1].Y, 720f / n, vertices[k - n - 1].Y - vertices[k + n + 1].Y).Normalized();
            }
        var indices = new int[n * n * 6];
        for (int j = 0; j < n; j++)
            for (int i = 0; i < n; i++)
            {
                int a = j * (n + 1) + i, k = (j * n + i) * 6;
                indices[k] = a; indices[k + 1] = a + 1; indices[k + 2] = a + n + 1;
                indices[k + 3] = a + 1; indices[k + 4] = a + n + 2; indices[k + 5] = a + n + 1;
            }
        var arrays = new Godot.Collections.Array(); arrays.Resize((int)Mesh.ArrayType.Max);
        arrays[(int)Mesh.ArrayType.Vertex] = vertices; arrays[(int)Mesh.ArrayType.Normal] = normals;
        arrays[(int)Mesh.ArrayType.TexUV] = uv; arrays[(int)Mesh.ArrayType.Index] = indices;
        var mesh = new ArrayMesh(); mesh.AddSurfaceFromArrays(Mesh.PrimitiveType.Triangles, arrays);
        ResourceSaver.Save(mesh, terrainPath);
        InstallTerrain(mesh, layout);
    }
    private void InstallTerrain(ArrayMesh mesh, Texture2D layout)
    {
        var material = new ShaderMaterial { Shader = GD.Load<Shader>("res://maps/seabreeze_village/terrain.gdshader") };
        material.SetShaderParameter("layout_map", layout);
        var node = new MeshInstance3D { Name = "ProceduralTerrain", Mesh = mesh, MaterialOverride = material, CastShadow = GeometryInstance3D.ShadowCastingSetting.Off };
        AddChild(node);
        node.CreateTrimeshCollision();
    }
    public string SurfaceAt(float x, float z)
    {
        double relative = z - CurveValue(x);
        if (x > -9 && x < -3.8f && relative > -8.5 && relative < 7) return "dirt";
        if (RoadInfo(x, z).D < 4.3f) return "road";
        if (relative < -27 && z < -4) return "sea";
        var p = new Vector2(x, z);
        if (Zones["paddy"].HasPoint(p) || Zones["paddy_in"].HasPoint(p)) return "paddy";
        if (Zones["street"].HasPoint(p) || Zones["pave"].HasPoint(p)) return "concrete";
        if (Zones["yard"].HasPoint(p)) return "hardpack";
        if (Zones["bed"].HasPoint(p) || z > 40 && RailDistance(x, z) < 3.5f) return "gravel";
        return "grass";
    }
}
