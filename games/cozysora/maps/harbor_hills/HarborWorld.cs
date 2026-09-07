using Godot;

namespace CozySora;

/// <summary>A 360 metre waterfront district, with graded building pads and continuous streets.</summary>
public partial class HarborWorld : CozyMap
{
    public static readonly float[] StreetsX = [-76, 8, 90];
    public static readonly float[] StreetsZ = [-102, -32, 46, 106];
    public Node3D StaticContent { get; private set; } = null!;
    private HarborGeometry _geometry = null!;
    private HarborTransit? _transit;
    private readonly List<MeshInstance3D> _fogBanks = new();
    private double _time;
    private sealed record Terrace(Vector2 Center, float Yaw, float HalfWidth, float Back, float Front, float Level);
    private readonly Dictionary<Vector2I, List<Terrace>> _terraceCells = new();
    private readonly List<(Vector2 Center, Vector2 Forward)> _streetEnds = new();

    public override async Task Build()
    {
        GenerationSignature = CozySceneCache.Signature("res://maps/harbor_hills");
        foreach (float x in StreetsX) _streetEnds.Add((new(x, 134), new(0, 1)));
        foreach (float z in StreetsZ)
        {
            _streetEnds.Add((new(-119, z), new(-1, 0)));
            _streetEnds.Add((new(128, z), new(1, 0)));
        }
        foreach (var plot in HarborNeighborhood.Plots())
        {
            var turn = new Basis(Vector3.Up, plot.Yaw);
            var front = new Vector3(plot.X, 0, plot.Z) + turn * new Vector3(0, 0, plot.Depth * .5f + 2);
            float depth = Mathf.Abs(Mathf.Cos(plot.Yaw)) > .5f ? 2.4f : 3.8f;
            var pad = new Terrace(new(plot.X, plot.Z), plot.Yaw, plot.Width * .5f + .13f,
                -plot.Depth * .5f, plot.Depth * .5f + depth, TerrainHeight(front.X, front.Z) + .15f);
            for (int x = Mathf.FloorToInt((plot.X - 15) / 16); x <= Mathf.FloorToInt((plot.X + 15) / 16); x++)
                for (int z = Mathf.FloorToInt((plot.Z - 15) / 16); z <= Mathf.FloorToInt((plot.Z + 15) / 16); z++)
                {
                    var cell = new Vector2I(x, z);
                    if (!_terraceCells.TryGetValue(cell, out var pads)) _terraceCells.Add(cell, pads = new());
                    pads.Add(pad);
                }
        }
        SupportsSurfaceTraversal = true;
        FlightBounds = new(new(-178, -1, -178), new(356, 157, 356));
        Ambience = new()
        {
            ["wind_gain"] = .16,
            ["wave_base"] = .032,
            ["wave_swell"] = .014,
            ["cicada_frequencies"] = new Vector2(3200, 3600),
            ["cicada_gain"] = 0.0,
            ["birds"] = true
        };
        ScenicViews = new()
        {
            ["waterfront"] = [-36, -111, 4, -.78f, .04f],
            ["commercial"] = [8, -68, 5, 1.57f, .02f],
            ["residential"] = [77, 39.7f, 29, 1.57f, -.04f],
            ["park"] = [-105, 96, 58, -.2f, -.19f],
            ["cable_car"] = [16, -98, 32, 1.32f, -.02f],
            ["stairs"] = [-39, 49, 38, 3.14f, .23f],
            ["garden"] = [-34, -68, 29, 1.75f, -.03f],
            ["rooftops"] = [51, -10, 45, 1.8f, -.28f],
            ["flight"] = [-48, 105, 88, -.25f, -.52f],
            ["street_end"] = [94, 125, 0, 3.14f, -.1f],
            ["top"] = [0, 5, 305, 0, -1.57f]
        };
        foreach (string key in new[] { "commercial", "residential", "park", "cable_car", "stairs", "garden", "street_end" })
        {
            var view = ScenicViews[key];
            view[2] = HeightAt(view[0], view[1]) + (key == "park" ? 2 : key is "residential" or "garden" or "cable_car" ? 0 : 1);
        }
        var atmosphere = GD.Load<CozyAtmosphere>("res://maps/harbor_hills/atmosphere.tres");
        atmosphere.Install(this);
        ReportProgress("Finding the way to Harbor Hills…", .08f);
        await NextFrame();
        string cache = "user://harbor_hills_" + GenerationSignature + ".scn";
        if (Godot.FileAccess.FileExists(cache))
        {
            StaticContent = GD.Load<PackedScene>(cache).Instantiate<Node3D>();
            AddChild(StaticContent);
            GD.Print("Harbor Hills static cache restored: ", cache);
        }
        else
        {
            StaticContent = new Node3D { Name = "Harbor Hills district" };
            AddChild(StaticContent);
            _geometry = new HarborGeometry(StaticContent) { GroundHeight = HeightAt, PlantClearance = RoadEndContains };
            Terrain();
            BackdropLand();
            ReportProgress("Paving streets above the bay…", .22f);
            await NextFrame();
            Streets();
            await new HarborNeighborhood().Build(this, _geometry);
            ReportProgress("Growing the cypress gardens…", .72f);
            await NextFrame();
            new HarborNature().Build(this, _geometry);
            new HarborDetails().Build(this, _geometry);
            _geometry.Finish();
            CozySceneCache.Save(StaticContent, cache);
            GD.Print("Harbor Hills district generated: ", cache);
            _geometry = null!;
        }
        var sea = WaterSurfaces.FirstOrDefault();
        if (sea != null)
            foreach (var prop in StaticContent.GetChildren().OfType<Node3D>().Where(n => n.HasMeta("water_float")))
                CozyWaterFloat.Attach(prop, sea, prop.HasMeta("water_offset") ? (float)prop.GetMeta("water_offset") : .25f);
        ReportProgress("Ringing the last departure bell…", .92f);
        await NextFrame();
        _transit = new HarborTransit();
        AddChild(_transit);
        _transit.Build(this);
        FogBanks();
        var air = GD.Load<CozyAirParticles>("res://maps/harbor_hills/air.tres");
        foreach (var at in new Vector2[] { new(-53, 106), new(-108, 78), new(-40, -68), new(52, 7) }) air.Install(this, Point(at.X, at.Y, 1.5f));
        atmosphere.InstallPost(this);
        ReportProgress("The bay is waiting.", 1);
    }

    public float TerrainHeight(float x, float z)
    {
        if (z < -119) return -3.5f;
        float t = Mathf.Clamp((z + 105) / 205, 0, 1);
        float rise = 44 * t * t * (3 - 2 * t);
        float hill = 12 * Mathf.Exp(-Mathf.Pow((x + 90) / 75, 2) - Mathf.Pow((z - 69) / 70, 2)) * Mathf.SmoothStep(-90, 0, z);
        return 3 + rise + hill;
    }

    public override float HeightAt(float x, float z)
    {
        foreach (float stairX in new[] { -38f, -104f })
            if (Mathf.Abs(x - stairX) < 2.6f && z >= 47 && z <= 91)
            {
                float landing = stairX == -104 ? TerrainHeight(-110, 99) : TerrainHeight(x, 91);
                return Mathf.Lerp(TerrainHeight(x, 47), landing, (z - 47) / 44);
            }
        bool publicWay = false;
        foreach (float street in StreetsX) if (Mathf.Abs(x - street) < 8.3f) publicWay = true;
        foreach (float street in StreetsZ) if (Mathf.Abs(z - street) < 8.3f) publicWay = true;
        if (!publicWay && _terraceCells.TryGetValue(new(Mathf.FloorToInt(x / 16), Mathf.FloorToInt(z / 16)), out var pads))
            foreach (var pad in pads)
            {
                if (Mathf.Abs(x - pad.Center.X) > 15 || Mathf.Abs(z - pad.Center.Y) > 15) continue;
                var local = (new Vector2(x, z) - pad.Center).Rotated(pad.Yaw);
                float edge = Mathf.Max(Mathf.Abs(local.X) - pad.HalfWidth, Mathf.Max(pad.Back - local.Y, local.Y - pad.Front));
                if (edge < .75f) return Mathf.Min(TerrainHeight(x, z), Mathf.Lerp(pad.Level, TerrainHeight(x, z), Mathf.SmoothStep(0, .75f, edge)));
            }
        float ground = TerrainHeight(x, z);
        foreach (float courtX in new[] { -40f, 52f })
            foreach (float courtZ in new[] { -68f, 7f })
            {
                float radius = new Vector2(x - courtX, z - courtZ - 1).Length();
                if (radius < 5.5f) return Mathf.Lerp(TerrainHeight(courtX, courtZ + 1), ground, Mathf.SmoothStep(3.4f, 5.5f, radius));
                foreach (int side in new[] { -1, 1 })
                {
                    float centerX = courtX + side * 14;
                    float edge = Mathf.Max(Mathf.Abs(x - centerX) - 4.1f, Mathf.Abs(z - courtZ) - 7);
                    if (edge < 2) return Mathf.Lerp(TerrainHeight(centerX, courtZ), ground, Mathf.SmoothStep(0, 2, edge));
                }
            }
        float overlook = new Vector2((x + 110) / 10.5f, (z - 99) / 8.5f).Length();
        if (overlook < 1.3f) return Mathf.Lerp(TerrainHeight(-110, 99), ground, Mathf.SmoothStep(1, 1.3f, overlook));
        if (x > -120 && x < -108 && z < -119 && z > -163) return 2.65f;
        return TerrainHeight(x, z);
    }

    public override bool Walkable(float x, float z) =>
        x > -119.5f && x < -108.5f && z > -162 && z < -116 || Mathf.Abs(x) < 171 && z > -116.5f && z < 170;

    public override void SetPaused(bool value)
    {
        if (IsInstanceValid(_transit)) _transit!.SetPaused(value);
    }

    public Vector3 Point(float x, float z, float offset = 0) => new(x, HeightAt(x, z) + offset, z);

    private void Terrain()
    {
        var surface = new SurfaceTool();
        surface.Begin(Mesh.PrimitiveType.Triangles);
        for (int iz = 0; iz < 360; iz++)
            for (int ix = 0; ix < 360; ix++)
            {
                float x = -180 + ix, z = -180 + iz;
                var a = Point(x, z); var b = Point(x + 1, z); var c = Point(x + 1, z + 1); var d = Point(x, z + 1);
                foreach (var point in new[] { a, b, c, a, c, d }) surface.AddVertex(point);
            }
        surface.GenerateNormals();
        var mesh = surface.Commit();
        StaticContent.AddChild(new MeshInstance3D
        {
            Mesh = mesh,
            MaterialOverride = new ShaderMaterial { Shader = GD.Load<Shader>("res://maps/harbor_hills/ground.gdshader") }
        });
        CozyCollision.Mesh(_geometry.Collision, mesh);
        _geometry.Box(new(0, 0, -119), new(352, 6.4f, 2.2f), "7c827b", true, 0, "brick");
        _geometry.Box(new(0, 3.18f, -119), new(352, .28f, 2.6f), "d0c7ac");
        List<Vector3> path = new();
        for (int x = -174; x < 175; x += 2) path.Add(Point(x, -113, .09f));
        _geometry.Ribbon(path, 9, "c3bda6", true);
        foreach (float x in new[] { -147f, 151f })
        {
            path = new();
            for (int z = -104; z < 165; z += 2) path.Add(Point(x + Mathf.Sin(z * .018f) * 9, z, .05f));
            _geometry.Ribbon(path, 3.4f, "bcad8e", true);
        }
    }

    private void BackdropLand()
    {
        foreach (var rect in new Rect2[] { new(-620, -119, 440, 739), new(180, -119, 440, 739), new(-180, 180, 360, 440) })
        {
            var surface = new SurfaceTool();
            surface.Begin(Mesh.PrimitiveType.Triangles);
            for (int iz = 0; iz < Mathf.CeilToInt(rect.Size.Y / 4); iz++)
                for (int ix = 0; ix < Mathf.CeilToInt(rect.Size.X / 4); ix++)
                {
                    float x = rect.Position.X + ix * 4, z = rect.Position.Y + iz * 4;
                    Vector2[] corners = [new(x, z), new(x + 4, z), new(x + 4, z + 4), new(x, z + 4)];
                    Vector3[] positions = new Vector3[4];
                    for (int i = 0; i < 4; i++)
                    {
                        var p = corners[i];
                        float outside = Mathf.Max(Mathf.Abs(p.X) - 180, p.Y - 180);
                        positions[i] = new(p.X, TerrainHeight(p.X, p.Y) + Mathf.SmoothStep(0, 110, outside) *
                            (12 + 11 * Mathf.Sin(p.X * .009f) * Mathf.Sin(p.Y * .012f)), p.Y);
                    }
                    foreach (int i in new[] { 0, 1, 2, 0, 2, 3 }) surface.AddVertex(positions[i]);
                }
            surface.GenerateNormals();
            StaticContent.AddChild(new MeshInstance3D { Mesh = surface.Commit(), MaterialOverride = _geometry.Material("71866d") });
        }
        for (int i = 0; i < 42; i++)
        {
            float x = -157 + i * 8, z = 199 + i % 3 * 14;
            float y = TerrainHeight(x, z), height = 7 + i % 5 * 1.6f;
            _geometry.Box(new(x, y + height * .5f, z), new(7, height, 10), new[] { "929e90", "a2a38e", "91a5a3", "b1a393" }[i % 4]);
            _geometry.Box(new(x, y + height + .2f, z), new(7.5f, .4f, 10.5f), "77897f");
            for (int row = 0; row < 2; row++)
                for (int col = 0; col < 3; col++) _geometry.Box(new(x - 2 + col * 2, y + 2 + row * 3, z - 5.03f), new(.9f, 1.2f, .04f), "607d7e");
        }
    }

    private void Streets()
    {
        foreach (float x in StreetsX)
        {
            List<Vector3> path = new();
            for (int z = -108; z < 135; z += 2) path.Add(Point(x, z, .025f));
            _geometry.Ribbon(path, 10.8f, "5c5e5a", false, true, "asphalt");
            foreach (int side in new[] { -1, 1 })
            {
                Sidewalk(x + side * 6.8f, true, -108, 134, StreetsZ);
                path = new();
                for (int z = -108; z < 135; z += 2) path.Add(Point(x + side * 5.45f, z, .13f));
                _geometry.Ribbon(path, .2f, "ddd4bd");
            }
            for (int z = -93; z < 130; z += 9)
            {
                bool crossing = false;
                foreach (float cross in StreetsZ) if (Mathf.Abs(z - cross) < 7) crossing = true;
                if (!crossing)
                    foreach (float dx in new[] { -.15f, .15f })
                        _geometry.Ribbon([Point(x + dx, z, .04f), Point(x + dx, z + 3, .04f)], .09f, "d4b563");
            }
        }
        foreach (float z in StreetsZ)
        {
            List<Vector3> path = new();
            for (int x = -119; x < 129; x++) path.Add(Point(x, z, .032f));
            _geometry.Ribbon(path, 10.8f, "5c5e5a", false, true, "asphalt");
            foreach (int side in new[] { -1, 1 }) Sidewalk(z + side * 6.8f, false, -119, 128, StreetsX);
            foreach (float streetX in StreetsX)
                foreach (int side in new[] { -1, 1 })
                    for (int stripe = -4; stripe < 5; stripe++)
                        _geometry.Ribbon([Point(streetX + stripe, z + side * 6 - .9f, .051f), Point(streetX + stripe, z + side * 6 + .9f, .051f)], .5f, "e3dcc5");
        }
        foreach (var (center, forward) in _streetEnds)
        {
            _geometry.Semicircle(center, forward, 0, 5.4f, .032f, "5c5e5a", false, "asphalt");
            _geometry.Semicircle(center, forward, 5.4f, 8.2f, .172f, "b9b7a5", true, "paving");
            _geometry.Semicircle(center, forward, 5.35f, 5.55f, .18f, "ddd4bd");
        }
        foreach (float dx in new[] { -.76f, .76f, 0 })
        {
            List<Vector3> path = new();
            for (int z = -103; z < 93; z++) path.Add(Point(8 + dx, z, .052f));
            _geometry.Ribbon(path, dx != 0 ? .065f : .1f, dx != 0 ? "a2a6a0" : "303c40");
        }
        List<Vector3> circle = new();
        for (int i = 0; i < 65; i++)
        {
            float angle = Mathf.Tau * i / 64;
            circle.Add(Point(8 + Mathf.Sin(angle) * 5, 96 + Mathf.Cos(angle) * 5, .075f));
        }
        _geometry.Ribbon(circle, .08f, "abb0a6");
        _geometry.Add("cylinder", Point(8, 96, .015f), new(9.7f, .09f, 9.7f), "635e50");
    }

    public bool RoadEndContains(float x, float z, float margin = 0)
    {
        foreach (var (center, forward) in _streetEnds)
        {
            var delta = new Vector2(x, z) - center;
            if (delta.Dot(forward) >= -margin && delta.LengthSquared() < Mathf.Pow(8.2f + margin, 2)) return true;
        }
        return false;
    }

    private void Sidewalk(float fixedCoordinate, bool vertical, int start, int end, float[] crossings)
    {
        List<Vector3> path = new();
        for (int coordinate = start; coordinate <= end; coordinate++)
        {
            float distance = 1000;
            foreach (float cross in crossings) distance = Mathf.Min(distance, Mathf.Abs(coordinate - cross));
            bool stairCrossing = !vertical && Mathf.Abs(fixedCoordinate - 52.8f) < .1f &&
                (Mathf.Abs(coordinate + 104) < 2.6f || Mathf.Abs(coordinate + 38) < 2.6f || Mathf.Abs(coordinate + 56) < 1.5f);
            if (distance < 5.2f || stairCrossing)
            {
                if (path.Count > 1) _geometry.Ribbon(path, 2.8f, "b9b7a5", true, true, "paving");
                path = new();
                continue;
            }
            float lift = .032f + .14f * Mathf.SmoothStep(8.2f, 10.5f, distance);
            path.Add(vertical ? Point(fixedCoordinate, coordinate, lift) : Point(coordinate, fixedCoordinate, lift));
        }
        if (path.Count > 1) _geometry.Ribbon(path, 2.8f, "b9b7a5", true, true, "paving");
    }

    private void FogBanks()
    {
        for (int i = 0; i < 9; i++)
        {
            var material = new ShaderMaterial { Shader = GD.Load<Shader>("res://maps/harbor_hills/fog.gdshader") };
            material.SetShaderParameter("phase", i * 1.7f);
            var fog = new MeshInstance3D
            {
                Mesh = new QuadMesh { Size = new(150 + i * 9, 20 + i * 2) },
                MaterialOverride = material,
                Position = new(-260 + i * 72, 6 + i % 3 * 4, -170 - i % 3 * 75),
                Rotation = new(-.13f, 0, 0),
                CastShadow = GeometryInstance3D.ShadowCastingSetting.Off
            };
            AddChild(fog);
            _fogBanks.Add(fog);
        }
    }

    public override void _Process(double delta)
    {
        _time += delta;
        for (int i = 0; i < _fogBanks.Count; i++)
        {
            var fog = _fogBanks[i];
            fog.Position = new(-260 + i * 72 + (float)Math.Sin(_time * .013 + i) * 33, fog.Position.Y, fog.Position.Z);
        }
    }
}
