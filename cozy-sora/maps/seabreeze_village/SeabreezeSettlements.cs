using Godot;

namespace CozySora;

public partial class SeabreezeSettlements : Node3D
{
    private SeabreezeWorld _world = null!;
    private readonly RandomNumberGenerator _rng = new();
    private readonly SeabreezeFinishes _finishes = new();
    private readonly List<Node3D> _trainCars = new(), _butterflies = new();
    private readonly Curve3D _track = new();
    private float _elapsed = 3, _trainStart = .92f;
    private sealed record HouseRow(float X, float Z, float Width, float Depth, string Tint, string Kind, float Yaw = 0, bool Hip = false);
    private sealed record ShopRow(float X, float Z, float Width, string Tint, string Name);
    private async Task NextFrame() => await ToSignal(GetTree(), SceneTree.SignalName.ProcessFrame);
    private MeshInstance3D B(Node3D parent, Vector3 position, Vector3 size, string color, bool collision = false) => CozyPrimitives.Box(parent, position, size, M(color), collision);
    private static MeshInstance3D B(Node3D parent, Vector3 position, Vector3 size, Material material, bool collision = false) => CozyPrimitives.Box(parent, position, size, material, collision);
    public async Task Build(SeabreezeWorld world)
    {
        _world = world;
        _rng.Seed = 808;
        Farm();
        await NextFrame();
        Village();
        await NextFrame();
        Shrine();
        await NextFrame();
        Paddies();
        await NextFrame();
        VendingArea();
        await NextFrame();
        Railway();
        await NextFrame();
        CozyMeshBatches.MergeStatic(this, _trainCars.Concat(_butterflies).ToList());
    }
    private StandardMaterial3D M(string hex)
    {
        return _world.Palette.Color(hex);
    }
    private MeshInstance3D C(Node3D p, Vector3 pos, float r, float h, string color, float top = -1.0f)
    {
        return CozyPrimitives.Cylinder(p, pos, r, (top < 0 ? r : top), h, M(color));
    }
    private Node3D Group(float x, float z, float yaw = 0.0f)
    {
        var n = new Node3D();
        AddChild(n);
        n.Position = new Vector3(x, _world.HeightAt(x, z), z);
        n.Rotation = new Vector3(0, yaw, 0);
        return n;
    }
    private void Line(Node3D p, Vector3 a, Vector3 q, float thickness, string color)
    {
        if (color == "#79573d")
        {
            float length = a.DistanceTo(q);
            var frame = new Node3D();
            p.AddChild(frame);
            frame.Position = (a + q) * .5f;
            frame.Quaternion = new Quaternion(Vector3.Up, (q - a).Normalized());
            if (thickness <= .18f && length > 3)
            {
                B(frame, Vector3.Zero, new Vector3(thickness * 1.8f, length, .16f), _finishes.Surface("paint", color));
                foreach (var side in new[] { -1, 1 })
                {
                    B(frame, new Vector3(side * thickness * .82f, 0, 0), new Vector3(.065f, length, .11f), _finishes.Surface("paint", color));
                }
                int sections = Mathf.CeilToInt(length / .60f);
                for (int i = 0; i < sections; i += 1)
                {
                    float y0 = -length * .5f + length * i / sections;
                    float y1 = -length * .5f + length * (i + 1) / sections;
                    float side = (i % 2 == 0 ? -1 : 1);
                    var begin = new Vector3(side * thickness * .82f, y0, 0);
                    var end = new Vector3(-side * thickness * .82f, y1, 0);
                    var web = B(frame, (begin + end) * .5f, new Vector3(.045f, begin.DistanceTo(end), .045f), M("#664938"));
                    web.Quaternion = new Quaternion(Vector3.Up, (end - begin).Normalized());
                }
            }
            else
            {
                B(frame, Vector3.Zero, new Vector3(thickness * 2, length, thickness * 2), _finishes.Surface("paint", color));
            }
        }
        else
        {
            CozyPrimitives.Beam(p, a, q, thickness, M(color));
        }
    }
    private Node3D Roof(Node3D p, Vector3 center, float width, float depth, float rise, string tint = "#515a60", bool hip = false, float curved = 0.0f, string trim_tint = "")
    {
        var n = new Node3D();
        p.AddChild(n);
        n.Position = center;
        var mesh = new SurfaceTool();
        mesh.Begin(Mesh.PrimitiveType.Triangles);
        var trim = (trim_tint.Length == 0 ? tint : trim_tint);
        var half = width * .5f;
        var ridge = (hip ? Mathf.Max(.25f, half - depth * .5f) : half);
        // Build the curved roof profile in two dimensions: the corners turn upward
        // more strongly than the center of an eave, which keeps the Japanese silhouette.
        foreach (var side in new[] { -1.0f, 1.0f })
        {
            for (int j = 0; j < 10; j += 1)
            {
                for (int ix = 0; ix < 10; ix += 1)
                {
                    var t0 = j / 10.0f;
                    var t1 = (j + 1) / 10.0f;
                    var u0 = -1.0f + ix * .2f;
                    var u1 = u0 + .2f;
                    var a = RoofPoint(half, ridge, depth, rise, curved, side, t0, u0, hip);
                    var q = RoofPoint(half, ridge, depth, rise, curved, side, t0, u1, hip);
                    var d = RoofPoint(half, ridge, depth, rise, curved, side, t1, u1, hip);
                    var e = RoofPoint(half, ridge, depth, rise, curved, side, t1, u0, hip);
                    if (side > 0)
                    {
                        Quad(mesh, a, q, d, e);
                    }
                    else
                    {
                        Quad(mesh, q, a, e, d);
                    }
                }
            }
        }
        if (hip)
        {
            Triangle(mesh, new Vector3(half, 0, -depth * .5f), new Vector3(half, 0, depth * .5f), new Vector3(ridge, rise, 0));
            Triangle(mesh, new Vector3(-half, 0, depth * .5f), new Vector3(-half, 0, -depth * .5f), new Vector3(-ridge, rise, 0));
        }
        else if (curved <= 1.2f)
        {
            foreach (var sx in new[] { -1, 1 })
            {
                Triangle(mesh, new Vector3(sx * half, 0, -depth * .5f), new Vector3(sx * half, 0, depth * .5f), new Vector3(sx * half, rise, 0));
            }
        }
        mesh.GenerateNormals();
        var roofmesh = new MeshInstance3D();
        roofmesh.Mesh = mesh.Commit();
        var mat = _finishes.Surface("tile", tint);
        mat.CullMode = BaseMaterial3D.CullModeEnum.Disabled;
        roofmesh.MaterialOverride = mat;
        n.AddChild(roofmesh);
        B(n, new Vector3(0, rise + .07f, 0), new Vector3(ridge * 2 + .12f, .19f, .23f), trim);
        foreach (var side in new[] { -1, 1 })
        {
            B(n, new Vector3(0, -.065f, side * depth * .5f), new Vector3(width + .06f, .16f, .16f), trim);
            // Cylindrical rolled tiles along the visible eaves.
            for (int i = 0; i < (int)(width / .28f); i += 1)
            {
                var edge = C(n, new Vector3(-half + .14f + i * .28f, .015f, side * (depth * .5f - .09f)), .075f, .32f, tint);
                edge.Rotation = new Vector3(Mathf.Pi / 2, 0, 0);
            }
        }
        return n;
    }
    private void Triangle(SurfaceTool st, Vector3 a, Vector3 q, Vector3 d)
    {
        foreach (var v in new[] { a, q, d })
        {
            st.SetUV(new Vector2(v.X, v.Z) * .4f);
            st.AddVertex(v);
        }
    }
    private void Quad(SurfaceTool st, Vector3 a, Vector3 q, Vector3 d, Vector3 e)
    {
        Triangle(st, a, q, d);
        Triangle(st, a, d, e);
    }
    private void Window(Node3D p, Vector3 at, float width = 1.7f, float height = 1.3f)
    {
        B(p, at, new Vector3(width + .15f, height + .15f, .08f), "#494739");
        B(p, at + new Vector3(0, 0, .055f), new Vector3(width, height, .035f), "#738d91");
        foreach (var x in new[] { -width * .5f, 0, width * .5f })
        {
            B(p, at + new Vector3(x, 0, .09f), new Vector3(.055f, height + .06f, .045f), "#c0bba5");
        }
        B(p, at + new Vector3(0, 0, .095f), new Vector3(width, .045f, .035f), "#c0bba5");
        B(p, at + new Vector3(0, -height * .5f - .08f, .1f), new Vector3(width + .27f, .11f, .22f), "#898e88");
    }
    private Node3D House(float x, float z, float width, float depth, string tint, string kind, float yaw, bool balcony = true, bool hip = false, int floors = 2, string roof_color = "")
    {
        var n = Group(x, z, yaw);
        var h = floors * 2.9f;
        B(n, new Vector3(0, h * .5f, 0), new Vector3(width, h, depth), _finishes.Surface((kind == "stone" ? "plaster" : kind), tint), true);
        B(n, new Vector3(0, .17f, 0), new Vector3(width + .2f, .35f, depth + .2f), _finishes.Surface("stone", "#8f8b7d"));
        foreach (var sx in new[] { -1, 1 })
        {
            foreach (var sz in new[] { -1, 1 })
            {
                B(n, new Vector3(sx * width * .49f, h * .5f, sz * depth * .49f), new Vector3(.16f, h, .16f), "#3f3128");
            }
        }
        for (int floor_no = 0; floor_no < floors; floor_no += 1)
        {
            var fy = floor_no * 2.9f;
            if (floor_no > 0)
            {
                B(n, new Vector3(0, fy, 0), new Vector3(width + .08f, .18f, depth + .08f), "#493a2e");
            }
            foreach (var side in new[] { -1, 1 })
            {
                var wall = new Node3D();
                n.AddChild(wall);
                wall.Rotation = new Vector3(0, (side == 1 ? 0 : Mathf.Pi), 0);
                foreach (var wx in new[] { -width * .28f, width * .28f })
                {
                    Window(wall, new Vector3(wx, fy + 1.7f, depth * .5f + .02f), Mathf.Min(1.8f, width * .25f), 1.25f);
                }
            }
            if (floor_no == 1 && balcony)
            {
                B(n, new Vector3(0, fy + .05f, depth * .5f + .47f), new Vector3(width - .5f, .16f, 1.05f), "#898e86");
                B(n, new Vector3(0, fy + .94f, depth * .5f + .95f), new Vector3(width - .45f, .08f, .075f), "#584f3e");
                for (int i = 0; i < (int)((width - .5f) / .23f); i += 1)
                {
                    B(n, new Vector3(-width * .5f + .3f + i * .23f, fy + .51f, depth * .5f + .95f), new Vector3(.035f, .83f, .035f), "#625c4f");
                }
                for (int panel = 0; panel < 3; panel += 1)
                {
                    var blind_width = width * .8f / 3 - .1f;
                    float wx = -width * .4f + blind_width * .5f + .05f + panel * (blind_width + .1f);
                    B(n, new Vector3(wx, 4.85f, depth * .5f + .92f), new Vector3(blind_width, 1.85f, .025f), _finishes.Surface("bamboo", "#817761"));
                    B(n, new Vector3(wx, 5.79f, depth * .5f + .92f), new Vector3(blind_width + .06f, .05f, .05f), "#3a382c");
                }
            }
        }
        // A recessed wooden sliding entrance with closely spaced battens.
        B(n, new Vector3(0, 1.22f, depth * .5f + .04f), new Vector3(1.65f, 2.15f, .08f), "#433b30");
        for (int i = 0; i < 13; i += 1)
        {
            B(n, new Vector3(-.77f + i * .128f, 1.22f, depth * .5f + .10f), new Vector3(.032f, 2.05f, .045f), "#988467");
        }
        B(n, new Vector3(0, .08f, depth * .5f + .42f), new Vector3(2, .15f, .85f), "#969689", true);
        if (Mathf.Abs(x + 10.5f) < .01f && Mathf.Abs(z - 84) < .01f)
        {
            Roof(n, new Vector3(0, h + .05f, 0), depth + 1.2f, width + 1.2f, (width + 1.2f) * .34f, "#3f484b", false, 0).Rotation = new Vector3(0, (Mathf.Pi / 2), 0);
            var gable = new SurfaceTool();
            gable.Begin(Mesh.PrimitiveType.Triangles);
            foreach (var side in new[] { -1, 1 })
            {
                Triangle(gable, new Vector3(-(width + 1.18f) * .5f, h + .05f, side * (depth * .5f + .605f)), new Vector3((width + 1.18f) * .5f, h + .05f, side * (depth * .5f + .605f)), new Vector3(0, h + .05f + (width + 1.2f) * .34f, side * (depth * .5f + .605f)));
            }
            gable.GenerateNormals();
            var cap = new MeshInstance3D();
            cap.Mesh = gable.Commit();
            cap.MaterialOverride = M("#c4bdac");
            n.AddChild(cap);
        }
        else
        {
            Roof(n, new Vector3(0, h + .03f, 0), width + 1.2f, depth + 1.2f, depth * .34f, (roof_color.Length != 0 ? roof_color : ((tint != "#d9d4bf" ? "#596366" : "#a6aaa4"))), hip, .3f, (roof_color.Length != 0 ? "#554330" : ""));
        }
        // Drainpipes and outdoor condenser are significant in close street views.
        B(n, new Vector3(width * .5f + .06f, h * .45f, depth * .42f), new Vector3(.09f, h * .9f, .09f), "#858b82");
        B(n, new Vector3(width * .34f, .61f, depth * .5f + .34f), new Vector3(.83f, .57f, .46f), "#cac9b9");
        var fan = C(n, new Vector3(width * .34f, .61f, depth * .5f + .59f), .21f, .022f, "#646c68");
        fan.Rotation = new Vector3(Mathf.Pi / 2, 0, 0);
        for (int j = 0; j < 4; j += 1)
        {
            B(n, new Vector3(width * .34f, .46f + j * .09f, depth * .5f + .61f), new Vector3(.65f, .015f, .015f), "#a2a69b");
        }
        return n;
    }
    private void Farm()
    {
        House(40.5f, 73.6f, 8, 6.5f, "#65503b", "wood", Mathf.Pi, false, true, 1, "#c0a578");
        var kura = Group(48, 72.5f, -.2f);
        B(kura, new Vector3(0, .6f, 0), new Vector3(5.6f, 2, 5.2f), "#49493e", true);
        Stonework(kura, 5.6f, 5.2f, 2, -.4f);
        B(kura, new Vector3(0, 3.8f, 0), new Vector3(4.8f, 5.6f, 4.4f), _finishes.Surface("wood", "#885f37"), true);
        B(kura, new Vector3(0, 6.2f, 0), new Vector3(4.79f, .8f, 4.39f), "#b4a993");
        foreach (var sx in new[] { -1, 1 })
        {
            foreach (var sz in new[] { -1, 1 })
            {
                B(kura, new Vector3(sx * 2.4f, 4.1f, sz * 2.2f), new Vector3(.19f, 5, .19f), "#5a4833");
            }
        }
        for (int xx = 0; xx < 47; xx += 1)
        {
            foreach (var sz in new[] { -1, 1 })
            {
                B(kura, new Vector3(-2.3f + xx * .1f, 3.8f, sz * 2.207f), new Vector3(.009f, 4.4f, .012f), "#5b3d27");
            }
        }
        foreach (var y in new[] { 2.9f, 4.3f, 5.8f })
        {
            B(kura, new Vector3(0, y, 0), new Vector3(4.9f, .10f, 4.5f), "#554635");
        }
        B(kura, new Vector3(0, 3.25f, 2.24f), new Vector3(2.2f, 2.8f, .10f), _finishes.Surface("wood", "#ad8f66"));
        foreach (var sx in new[] { -1, 1 })
        {
            B(kura, new Vector3(sx * 1.45f, 5.7f, 2.24f), new Vector3(.7f, .5f, .1f), "#282b23");
        }
        Roof(kura, new Vector3(0, 6.6f, 0), 6.6f, 6.4f, 3.17f, "#c4af7f", false, 1, "#584333");
        var awning = Group(40.5f, 70.35f);
        Roof(awning, new Vector3(0, 1.95f, 0), 7.6f, 6, .8f, "#c2ad7d", false, .6f, "#584333");
        foreach (var sx in new[] { -1, 1 })
        {
            B(awning, new Vector3(sx * 3.5f, .98f, -2.75f), new Vector3(.16f, 1.95f, .16f), "#4a3826");
        }
        House(47.5f, 79.5f, 2.6f, 2, "#c4c0b4", "metal", 0, false, false, 1).Scale = new Vector3(1, .73f, 1);
        C(this, new Vector3(45.6f, _world.HeightAt(45.6f, 79.1f) + .45f, 79.1f), .3f, .9f, "#3a6ac0");
        Car(43, 69.3f, .3f, true);
        Poles(new[] { new float[] { 80, 66, 9.5f }, new float[] { 66, 78, 10 }, new float[] { 55.2f, 70.8f, 9.6f, 1 }, new float[] { 52.4f, 68.6f, 10.2f } });
        Fence(new Vector2(30, 68), new Vector2(35.2f, 68), .5f, "#777b6c", false);
    }
    private void Village()
    {
        float street_y = _world.HeightAt(-20, 83);
        B(this, new Vector3(-10, street_y + .015f, 77), new Vector3(30, .012f, 3.7f), _finishes.Surface("asphalt", "#5e5754"));
        foreach (var z in new[] { 70.9f, 79.15f })
        {
            B(this, new Vector3(-11, street_y + .02f, z), new Vector3(48, .16f, .16f), "#a7a18b");
        }
        foreach (var x in new[] { -14.2f, -9.8f, -3, 1.6f })
        {
            B(this, new Vector3(x, street_y + .027f, 75.15f), new Vector3(.55f, .015f, .34f), "#273b3c");
            for (int i = 0; i < 7; i += 1)
            {
                B(this, new Vector3(x - .23f + i * .077f, street_y + .04f, 75.15f), new Vector3(.014f, .015f, .31f), "#697772");
            }
        }
        foreach (var data in new[] { new HouseRow(-35, 82.5f, 6.5f, 6.5f, "#a8aab0", "metal", Mathf.Pi, false), new HouseRow(-20.5f, 84, 7.5f, 7, "#70767c", "metal", -Mathf.Pi / 2, false), new HouseRow(-10.5f, 84, 8.5f, 7, "#b4bfc2", "metal", Mathf.Pi, false), new HouseRow(-1, 83.5f, 8, 6.5f, "#9aa3a8", "metal", Mathf.Pi, false), new HouseRow(8.5f, 84, 8, 7, "#846951", "wood", Mathf.Pi, true) })
        {
            House(data.X, data.Z, data.Width, data.Depth, data.Tint, data.Kind, data.Yaw, true, data.Hip);
        }
        foreach (var data in new[] { new HouseRow(-22, 59.5f, 9, 7, "#977b56", "wood"), new HouseRow(-31.5f, 55.5f, 8, 7, "#a8aab0", "metal"), new HouseRow(-12.5f, 58.4f, 8, 6, "#d9d4bf", "stone"), new HouseRow(-3.5f, 58, 7, 6, "#d9d4bf", "stone"), new HouseRow(-38, 92, 9, 7, "#826d4e", "wood"), new HouseRow(-8, 92.5f, 9, 7, "#8a8e8c", "metal"), new HouseRow(4, 91, 9, 7, "#c9c5b5", "stone") })
        {
            House(data.X, data.Z, data.Width, data.Depth, data.Tint, data.Kind, (data.Z < 65 ? 0 : Mathf.Pi), false, true);
        }
        // The north-facing shop facades, awnings, lanterns and narrow garden strip.
        foreach (var d in new[] { new ShopRow(-20.5f, 79.9f, 7.1f, "#776651", "SAKE"), new ShopRow(-10.5f, 79.95f, 7.8f, "#8a9298", "COZY STORE"), new ShopRow(-1, 79.8f, 6.8f, "#557578", "SORA") })
        {
            var n = Group(d.X, d.Z, Mathf.Pi);
            var aw = B(n, new Vector3(0, 2.65f, .62f), new Vector3(d.Width, .12f, 1.45f), d.Tint);
            aw.Rotation = new Vector3(-.12f, 0, 0);
            B(n, new Vector3(0, 2.9f, .11f), new Vector3(d.Width * .58f, .53f, .13f), "#c0b49b");
            Label(n, d.Name, new Vector3(0, 2.91f, .20f), .23f, "#514b3c");
            foreach (var i in new[] { -1, 1 })
            {
                MeshInstance3D lantern = CozyPrimitives.Sphere(n, new Vector3(i * (float)(d.Width) * .42f, 2.9f, .45f), new Vector3(.24f, .39f, .24f), M("#d45537"));
                Line(n, lantern.Position + new Vector3(0, .35f, 0), lantern.Position + new Vector3(0, .65f, 0), .015f, "#403c31");
            }
        }
        Poles(new[] { new float[] { -32, 79.5f, 10.5f }, new float[] { -13, 80.2f, 10.5f }, new float[] { 6, 80.2f, 10 } });
        foreach (var d in new[] { new[] { -28, 73.2f }, new[] { -27.2f, 86.9f }, new[] { -17f, 74f }, new[] { -7f, 74f }, new[] { 2, 73.5f } })
        {
            var n = Group(d[0], d[1]);
            for (int j = 0; j < 3; j += 1)
            {
                Crate(n, new Vector3(j * .53f, 0, 0), "#4d6967");
            }
        }
        foreach (var d in new[] { new[] { -11.2f, 73.6f }, new[] { -1.5f, 73.3f } })
        {
            var n = Group(d[0], d[1], .2f);
            for (int j = 0; j < 3; j += 1)
            {
                var size = new Vector3(.5f + (float)_rng.Randf() * .3f, .3f + (float)_rng.Randf() * .2f, .4f + (float)_rng.Randf() * .3f);
                B(n, new Vector3(0, j * .36f + size.Y * .5f, 0), size, (j % 2 == 0 ? "#b89d68" : "#8a6a48"), j == 0);
                B(n, new Vector3(0, j * .36f + size.Y + .01f, 0), new Vector3(size.X, .025f, .045f), "#837357");
            }
        }
        foreach (var d in new[] { new[] { -12.4f, 74.4f }, new[] { -15.2f, 75 }, new[] { .5f, 75.3f } })
        {
            Cone(d[0], d[1]);
        }
        VillageUtilityYard();
        Bicycle(-16, 79.7f, -1.4f, "#a94232");
        Bicycle(3.2f, 79.6f, -.1f, "#bfa345");
    }
    private Label3D Label(Node3D p, string text, Vector3 pos, float size, string tint)
    {
        var l = new Label3D();
        l.Text = text;
        l.Position = pos;
        l.PixelSize = size / 48.0f;
        l.FontSize = 48;
        l.Modulate = new Color(tint);
        l.OutlineSize = 0;
        l.NoDepthTest = false;
        p.AddChild(l);
        return l;
    }
    private void Shrine()
    {
        var n = Group(.5f, 23.5f, Mathf.Pi - .22f);
        B(n, new Vector3(0, -.65f, 0), new Vector3(6.6f, 1.4f, 6.4f), "#49493e", true);
        Stonework(n, 6.6f, 6.4f, 1.4f, -1.35f);
        B(n, new Vector3(0, .1f, 0), new Vector3(6.6f, .2f, 6.4f), _finishes.Surface("stone", "#d3cdbb"), true);
        B(n, new Vector3(0, .42f, 0), new Vector3(5.8f, .85f, 5.6f), _finishes.Surface("stone", "#c7c1ab"), true);
        B(n, new Vector3(0, 2.2f, 0), new Vector3(4.8f, 2.7f, 4.6f), "#beb9a5", true);
        foreach (var sx in new[] { -1, 1 })
        {
            for (int j = 0; j < 5; j += 1)
            {
                B(n, new Vector3(-2.4f + j * 1.2f, 2.2f, sx * 2.3f), new Vector3(.14f, 2.7f, .16f), "#58472e");
            }
            for (int j = 0; j < 4; j += 1)
            {
                B(n, new Vector3(sx * 2.4f, 2.2f, -2.3f + j * 1.533f), new Vector3(.16f, 2.7f, .14f), "#58472e");
            }
        }
        foreach (var y in new[] { .87f, 2.4f, 3.54f })
        {
            B(n, new Vector3(0, y, 0), new Vector3(4.9f, .16f, 4.7f), "#58472e");
        }
        B(n, new Vector3(0, 1.63f, 2.33f), new Vector3(4.3f, 1.47f, .08f), _finishes.Surface("wood", "#705339"));
        for (int i = 0; i < 21; i += 1)
        {
            B(n, new Vector3(-2.05f + i * .205f, 1.63f, 2.40f), new Vector3(.035f, 1.4f, .04f), "#5a4934");
        }
        Roof(n, new Vector3(0, 3.65f, 0), 6.7f, 6.5f, .75f, "#283238", true, .35f);
        Roof(n, new Vector3(0, 3.95f, 0), 5.9f, 5.2f, 2.392f, "#252d34", false, 1.6f).Rotation = new Vector3(0, Mathf.Pi / 2, 0);
        ShrineGable(n);
        B(n, new Vector3(0, .97f, 2.8f), new Vector3(3.36f, .25f, .9f), "#896644", true);
        House(8.5f, 31, 7, 5.5f, "#594b3d", "wood", Mathf.Pi - .15f, false, true, 1);
        foreach (var d in new[] { new[] { -4.2f, 24.5f }, new[] { 5.4f, 27 } })
        {
            var lantern = Group(d[0], d[1]);
            B(lantern, new Vector3(0, .15f, 0), new Vector3(.7f, .3f, .7f), "#9a9a89", true);
            C(lantern, new Vector3(0, .85f, 0), .18f, 1.1f, "#9a9a89", .14f);
            B(lantern, new Vector3(0, 1.45f, 0), new Vector3(.5f, .12f, .5f), "#9a9a89");
            B(lantern, new Vector3(0, 1.72f, 0), new Vector3(.42f, .42f, .42f), "#999c87");
            foreach (var sx in new[] { -1, 1 })
            {
                B(lantern, new Vector3(0, 1.74f, sx * .214f), new Vector3(.24f, .24f, .02f), "#42483c");
            }
            Roof(lantern, new Vector3(0, 2, 0), .74f, .74f, .32f, "#929989", true);
            CozyPrimitives.Sphere(lantern, new Vector3(0, 2.45f, 0), new Vector3(.1f, .1f, .1f), M("#a1a491"));
        }
        Fence(new Vector2(9, 22), new Vector2(9, 28), .7f, "#8b8c7a", false);
        Car(5.8f, 21.3f, Mathf.Pi - .25f, false);
        foreach (var d in new[] { new[] { 1.5f, 13.5f }, new[] { -1.5f, 15 }, new[] { 3.5f, 16.5f }, new[] { .5f, 18 }, new[] { 5.5f, 15 }, new[] { -2.5f, 12.8f }, new[] { 2.5f, 14.8f }, new[] { 7, 19.5f }, new[] { 8.5f, 20 }, new[] { 3, 20.5f } })
        {
            var fly = Group(d[0], d[1]);
            fly.Position = new Vector3(fly.Position.X, fly.Position.Y + _rng.RandfRange(1.1f, 2.0f), fly.Position.Z);
            fly.SetMeta("origin", fly.Position);
            fly.SetMeta("phase", (float)_rng.Randf() * Mathf.Tau);
            B(fly, new Vector3(-.07f, 0, 0), new Vector3(.14f, .018f, .15f), "#efd779");
            B(fly, new Vector3(.07f, 0, 0), new Vector3(.14f, .018f, .15f), "#efd779");
            _butterflies.Add(fly);
        }
    }
    private void Paddies()
    {
        PaddyGuardrail();
        foreach (var area in new[] { new Rect2(63.5f, -8, 35.5f, 52), new Rect2(42, 0, 10, 30) })
        {
            var water = new StandardMaterial3D();
            water.AlbedoColor = new Color("#77999a");
            water.Metallic = .28f;
            water.Roughness = .23f;
            B(this, new Vector3(area.GetCenter().X, .405f, area.GetCenter().Y), new Vector3(area.Size.X, .025f, area.Size.Y), water);
            var canopy = new MeshInstance3D();
            var canopy_mesh = new PlaneMesh();
            canopy_mesh.Size = area.Size - new Vector2(.8f, .8f);
            canopy.Mesh = canopy_mesh;
            canopy.Position = new Vector3(area.GetCenter().X, .95f, area.GetCenter().Y);
            var canopy_material = new ShaderMaterial();
            canopy_material.Shader = GD.Load<Shader>("res://maps/seabreeze_village/rice_canopy.gdshader");
            canopy.MaterialOverride = canopy_material;
            canopy.CastShadow = GeometryInstance3D.ShadowCastingSetting.Off;
            AddChild(canopy);
            // Three bent, tapered ribbons form each rice tuft above the distant canopy.
            var blades = new SurfaceTool();
            blades.Begin(Mesh.PrimitiveType.Triangles);
            for (int j = 0; j < 3; j += 1)
            {
                var yaw = j * Mathf.Tau / 3 + (float)_rng.Randf() * .8f;
                var direction = new Vector3(Mathf.Cos(yaw), 0, Mathf.Sin(yaw));
                var side = new Vector3(-direction.Z, 0, direction.X);
                var width = _rng.RandfRange(.10f, .15f);
                var bend = _rng.RandfRange(.2f, .6f);
                for (int section = 0; section < 4; section += 1)
                {
                    var t0 = section / 4.0f;
                    var t1 = (section + 1) / 4.0f;
                    var lower = new Vector3(0, t0, 0) + direction * bend * t0 * t0;
                    var upper = new Vector3(0, t1, 0) + direction * bend * t1 * t1;
                    var points = new[] { lower - side * width * (1 - t0) * .5f, lower + side * width * (1 - t0) * .5f, upper + side * width * (1 - t1) * .5f, lower - side * width * (1 - t0) * .5f, upper + side * width * (1 - t1) * .5f, upper - side * width * (1 - t1) * .5f };
                    foreach (var point in points)
                    {
                        blades.AddVertex(point);
                    }
                }
            }
            blades.GenerateNormals();
            var rice_mat = new ShaderMaterial();
            rice_mat.Shader = GD.Load<Shader>("res://maps/seabreeze_village/rice_blades.gdshader");
            var multi = new MultiMesh();
            multi.TransformFormat = MultiMesh.TransformFormatEnum.Transform3D;
            multi.Mesh = blades.Commit();
            var transforms = new List<Transform3D>();
            var rows = (int)((area.Size.X - 1.2f) / .35f);
            var cols = (int)((area.Size.Y - 1.2f) / .45f);
            for (int ix = 0; ix < rows; ix += 1)
            {
                for (int iz = 0; iz < cols; iz += 1)
                {
                    float x = area.Position.X + .6f + ix * .35f;
                    float z = area.Position.Y + .6f + iz * .45f;
                    if (area.Size.X > 20 && (Mathf.Abs(x - 81.2f) < .33f || Mathf.Abs(z - 17.8f) < .3f))
                    {
                        continue;
                    }
                    var scale_y = _rng.RandfRange(.7f, .9f);
                    var basis = new Basis(Vector3.Up, (float)_rng.Randf() * Mathf.Tau).Scaled(new Vector3(scale_y * 2.4f, scale_y, scale_y * 2.4f));
                    transforms.Add(new Transform3D(basis, new Vector3(x + _rng.RandfRange(-.04f, .04f), .42f, z + _rng.RandfRange(-.04f, .04f))));
                }
            }
            multi.InstanceCount = transforms.Count;
            for (int i = 0; i < transforms.Count; i += 1)
            {
                multi.SetInstanceTransform(i, transforms[i]);
            }
            var inst = new MultiMeshInstance3D();
            inst.CastShadow = GeometryInstance3D.ShadowCastingSetting.Off;
            inst.Multimesh = multi;
            inst.MaterialOverride = rice_mat;
            AddChild(inst);
            foreach (var z in new[] { area.Position.Y, area.End.Y })
            {
                B(this, new Vector3(area.GetCenter().X, .48f, z), new Vector3(area.Size.X + .5f, .17f, .4f), "#858660");
            }
            foreach (var x in new[] { area.Position.X, area.End.X })
            {
                B(this, new Vector3(x, .48f, area.GetCenter().Y), new Vector3(.4f, .17f, area.Size.Y), "#858660");
            }
            if (area.Size.X > 20)
            {
                B(this, new Vector3(81.2f, .48f, 18), new Vector3(.55f, .17f, 52), "#8a8860");
                B(this, new Vector3(81.2f, .48f, 17.8f), new Vector3(35.5f, .17f, .5f), "#8a8860");
            }
        }
        Fence(new Vector2(63.9f, -6), new Vector2(63.9f, 44), 1, "#5a6848", false);
        Fence(new Vector2(99.6f, -8), new Vector2(99.6f, 44), 1, "#5a6848", false);
        Fence(new Vector2(64.2f, 44.5f), new Vector2(99, 44.5f), 1.2f, "#888d85", true);
        Fence(new Vector2(64.2f, -8.5f), new Vector2(99, -8.5f), 1.2f, "#888d85", true);
        var cabinet = Group(61, 3.6f, -2.05f);
        B(cabinet, new Vector3(0, .125f, 0), new Vector3(1.6f, .25f, 1.15f), "#b9b6a8", true);
        B(cabinet, new Vector3(0, 1.25f, 0), new Vector3(1.4f, 2, .95f), "#d9642c", true);
        B(cabinet, new Vector3(0, .41f, 0), new Vector3(1.42f, .30f, .97f), "#b35b28");
        B(cabinet, new Vector3(0, 2.15f, 0), new Vector3(1.42f, .14f, .97f), "#e08a55");
        B(cabinet, new Vector3(0, 2.27f, 0), new Vector3(1.46f, .06f, 1.01f), "#b35b28");
        B(cabinet, new Vector3(0, 1.25f, .48f), new Vector3(.018f, 1.8f, .02f), "#8a4522");
        B(cabinet, new Vector3(.1f, 1.1f, .50f), new Vector3(.05f, .11f, .05f), "#2a302a");
        B(cabinet, new Vector3(.32f, 1.45f, .49f), new Vector3(.26f, .18f, .02f), "#cfcdc0");
        Poles(new[] { new float[] { 63.5f, 44, 10.5f, .1f, 1.0f }, new float[] { 64.9f, 7.4f, 9.6f, .25f, .85f }, new float[] { 61.6f, 4.7f, 10.8f, Mathf.Pi + .25f, 1.15f }, new float[] { 70.5f, -14, 10.5f, .35f, 1.0f } }, true);
        var lamp_origin = new Vector3(61.6f, _world.HeightAt(61.6f, 4.7f) + 7.56f, 4.7f);
        var lamp_direction = new Vector3(-.94f, 0, .34f).Normalized();
        var lamp_end = lamp_origin + lamp_direction * 1.7f + new Vector3(0, .35f, 0);
        Line(this, lamp_origin + lamp_direction * .1f, lamp_end, .05f, "#9a9b98");
        Line(this, lamp_origin - new Vector3(0, .7f, 0), lamp_origin + lamp_direction * .7f + new Vector3(0, .14f, 0), .03f, "#9a9b98");
        var lamp = new Node3D();
        AddChild(lamp);
        lamp.Position = lamp_end + lamp_direction * .2f + new Vector3(0, .02f, 0);
        lamp.Rotation = new Vector3(0, Mathf.Atan2(lamp_direction.X, lamp_direction.Z) - Mathf.Pi / 2, 0);
        B(lamp, new Vector3(0, .06f, 0), new Vector3(.62f, .17f, .28f), "#9a9b98");
        B(lamp, new Vector3(.06f, -.05f, 0), new Vector3(.42f, .06f, .24f), "#e8e4c8");
        var meter = Group(61.4f, 4.48f, Mathf.Atan2(-6.4f, -7.3f));
        B(meter, new Vector3(0, 3.1f, 0), new Vector3(.4f, .5f, .25f), "#b4b7b0");
    }
    private void Fence(Vector2 a, Vector2 q, float height, string color, bool wire)
    {
        var distance = a.DistanceTo(q);
        var steps = Math.Max(1, (int)(distance / 1.8f));
        var points = new List<Vector3>();
        for (int i = 0; i < steps + 1; i += 1)
        {
            var at = a.Lerp(q, (float)(i) / steps);
            var ground = new Vector3(at.X, _world.HeightAt(at.X, at.Y), at.Y);
            B(this, ground + new Vector3(0, height * .5f, 0), new Vector3((wire ? .075f : .13f), height, (wire ? .075f : .13f)), color);
            points.Add(ground);
            if (i > 0)
            {
                foreach (var y in (!wire ? new[] { .45f, .85f } : new[] { .12f, .52f, .92f }))
                {
                    Line(this, points[i - 1] + new Vector3(0, y * height, 0), ground + new Vector3(0, y * height, 0), (wire ? .025f : .045f), color);
                }
                if (wire)
                {
                    ChainlinkPanel(points[i - 1], ground, height);
                }
            }
        }
        var barrier = new Node3D();
        AddChild(barrier);
        barrier.Position = (points[0] + points[^1]) * .5f + new Vector3(0, height * .5f, 0);
        barrier.Rotation = new Vector3(0, Mathf.Atan2(-(q.Y - a.Y), q.X - a.X), 0);
        CozyCollision.StaticBox(barrier, Vector3.Zero, new Vector3(distance, height, .09f));
    }
    private void Poles(float[][] data, bool dark = false)
    {
        Vector3 previous = default;
        for (int i = 0; i < data.Length; i += 1)
        {
            var d = data[i];
            var n = Group(d[0], d[1]);
            float h = d[2];
            if (dark)
            {
                n.Rotation = new Vector3(0, d[3], 0);
                float radius = d[4];
                var shaft = C(n, new Vector3(0, h * .5f - .3f, 0), .19f * radius, h, "#696961", .12f * radius);
                shaft.MaterialOverride = _finishes.Surface("pole", "#78786d");
                for (int rung = 0; rung < 9; rung += 1)
                {
                    B(n, new Vector3(0, 2.5f + rung * .75f, 0), new Vector3(.05f, .05f, .42f), "#3a3b38");
                }
            }
            else
            {
                C(n, new Vector3(0, h * .5f, 0), .115f, h, "#7b8175", .08f);
            }
            B(n, new Vector3(0, h - .48f, 0), new Vector3(2.25f, .13f, .13f), "#656f68");
            B(n, new Vector3(0, h - 1.22f, 0), new Vector3(1.8f, .10f, .11f), "#656f68");
            foreach (var sx in new[] { -.9f, 0, .9f })
            {
                C(n, new Vector3(sx, h - .28f, 0), .072f, .26f, "#b3b9a7");
                C(n, new Vector3(sx, h - 1.05f, 0), .063f, .25f, "#b3b9a7");
            }
            if (!dark && d.Length > 3 && d[3] != 0)
            {
                foreach (var tx in new[] { .35f, -.35f })
                {
                    C(n, new Vector3(tx, h - 2, .22f), .22f, .75f, "#9c9d88");
                    C(n, new Vector3(tx, h - 1.6f, .22f), .25f, .065f, "#747966");
                }
            }
            B(n, new Vector3(0, h - 2.5f, .23f), new Vector3(.11f, .08f, .5f), "#68756b");
            if (i > 0)
            {
                foreach (var sx in new[] { -.9f, 0, .9f })
                {
                    WireSag(previous + new Vector3(sx, 0, 0), n.Position + new Vector3(sx, h - .15f, 0), 1.0f);
                }
                WireSag(previous - new Vector3(0, 1.7f, 0), n.Position + new Vector3(0, h - 1.85f, 0), 1.4f);
            }
            previous = n.Position + new Vector3(0, h - .15f, 0);
        }
    }
    private void WireSag(Vector3 a, Vector3 q, float sag)
    {
        var prev = a;
        for (int i = 1; i < 17; i += 1)
        {
            var t = i / 16.0f;
            var v = a.Lerp(q, t) - new Vector3(0, 4 * sag * t * (1 - t), 0);
            Line(this, prev, v, .015f, "#3a4543");
            prev = v;
        }
    }
    private Node3D VendingMachine(float x, float z, float yaw, string tint, bool worn = false)
    {
        var n = Group(x, z, yaw);
        B(n, new Vector3(0, 1, 0), new Vector3(1, 1.9f, .8f), _finishes.Surface("paint", tint), true);
        B(n, new Vector3(0, .035f, 0), new Vector3(.90f, .07f, .7f), "#222f2e");
        B(n, new Vector3(-.14f, 1.31f, .407f), new Vector3(.68f, .9f, .02f), "#263039");
        B(n, new Vector3(-.14f, 1.31f, .424f), new Vector3(.62f, .84f, .02f), "#1c2024");
        foreach (var yy in new[] { .87f, 1.748f })
        {
            B(n, new Vector3(-.14f, yy, .438f), new Vector3(.66f, .03f, .035f), "#bfc6bd");
        }
        var bottle_colors = new[] { "#d45742", "#e3bf53", "#3c787e", "#e7e4c6", "#5c9648" };
        for (int row = 0; row < (worn ? 5 : 3); row += 1)
        {
            for (int col = 0; col < (worn ? 11 : 9); col += 1)
            {
                float xx = -.42f + col * ((worn ? .055f : .069f));
                float yy = (worn ? (.98f + row * .165f) : (1.05f + row * .265f));
                var can_height = (worn ? _rng.RandfRange(.075f, .10f) : _rng.RandfRange(.12f, .19f));
                C(n, new Vector3(xx, yy, .458f), .022f, can_height, bottle_colors[(row + col) % 5]);
                C(n, new Vector3(xx, yy, .458f), .023f, .045f, "#e7e3cc");
                if ((float)_rng.Randf() > .35f)
                {
                    C(n, new Vector3(xx, yy + can_height * .5f + .01f, .458f), .010f, .024f, "#e4dfc9");
                }
                B(n, new Vector3(xx, yy - .105f, .455f), new Vector3(.052f, .015f, .03f), "#e5e6d8");
            }
        }
        for (int row = 0; row < 3; row += 1)
        {
            B(n, new Vector3(-.14f, 1.0f + row * .266f, .44f), new Vector3(.64f, .027f, .05f), "#c5ccc2");
            B(n, new Vector3(.35f, 1.63f - row * .09f, .419f), new Vector3(.11f, .05f, .025f), "#d7ddc5");
        }
        B(n, new Vector3(.32f, .95f, .42f), new Vector3(.16f, .08f, .03f), "#273737");
        B(n, new Vector3(.34f, .79f, .42f), new Vector3(.04f, .09f, .03f), "#273737");
        B(n, new Vector3(-.15f, .32f, .416f), new Vector3(.6f, .16f, .03f), "#1e3333");
        B(n, new Vector3(-.15f, .27f, .44f), new Vector3(.64f, .035f, .1f), "#a4b4af");
        Label(n, (tint == "#1f2f6c" ? "CUP" : ((tint == "#e8e6e0" ? "ICE" : "GM"))), new Vector3(-.13f, .56f, .426f), .13f, "#e6e9d4");
        return n;
    }
    private void VendingArea()
    {
        VendingMachine(-66.3f, 27.4f, Mathf.Pi / 2, "#e8e6e0");
        VendingMachine(-66.3f, 26.35f, Mathf.Pi / 2, "#1f2f6c");
        VendingMachine(-66.3f, 25.3f, Mathf.Pi / 2, "#c8262a");
        Fence(new Vector2(-67.2f, 10), new Vector2(-67.2f, 21.4f), 2.3f, "#7c8e85", true);
        Fence(new Vector2(-67.2f, 24.9f), new Vector2(-67.2f, 40), 2.3f, "#7c8e85", true);
        for (int j = 0; j < 2; j += 1)
        {
            var n = Group(-66.45f, 24.3f - j * .55f);
            for (int i = 0; i < 3; i += 1)
            {
                Crate(n, new Vector3(0, i * .33f, 0), ((j == 0 && i == 2) || (j == 1 && i == 1) ? "#c84040" : "#3a8a4a"));
            }
        }
        var boxes = Group(-66.25f, 29.4f, .3f);
        for (int i = 0; i < 3; i += 1)
        {
            B(boxes, new Vector3((i % 2) * .2f, .20f + i * .34f, 0), new Vector3(.48f, .37f, .44f), _finishes.Surface("wood", "#b0a17f"));
        }
        foreach (var d in new[] { new[] { -65.75f, 29.7f }, new[] { -65.65f, 27.4f }, new[] { -65.6f, 25 }, new[] { -65.7f, 21.7f } })
        {
            Cone(d[0], d[1]);
        }
        Poles(new[] { new float[] { -76.5f, 0, 8.4f }, new float[] { -76, 20.5f, 8.6f }, new float[] { -75.5f, 44, 8.6f } });
        Bicycle(-66.55f, 22.3f, -Mathf.Pi / 2, "#bfa345");
        var cone_points = new[] { new Vector2(-65.75f, 29.7f), new Vector2(-65.65f, 27.4f), new Vector2(-65.6f, 25), new Vector2(-65.7f, 21.7f) };
        for (int i = 0; i < 3; i += 1)
        {
            var a = cone_points[i];
            var q = cone_points[i + 1];
            HazardTape(new Vector3(a.X, _world.HeightAt(a.X, a.Y) + .42f, a.Y), new Vector3(q.X, _world.HeightAt(q.X, q.Y) + .42f, q.Y), .05f);
        }
        ViaductVending();
    }
    private void Crate(Node3D p, Vector3 pos, string tint)
    {
        B(p, pos + new Vector3(0, .15f, 0), new Vector3(.5f, .3f, .38f), tint);
        foreach (var y in new[] { .05f, .15f, .25f })
        {
            foreach (var sx in new[] { -1, 1 })
            {
                B(p, pos + new Vector3(sx * .251f, y, 0), new Vector3(.012f, .026f, .30f), "#243d35");
            }
        }
        for (int i = 0; i < 4; i += 1)
        {
            foreach (var sz in new[] { -1, 1 })
            {
                B(p, pos + new Vector3(-.18f + i * .12f, .15f, sz * .191f), new Vector3(.055f, .17f, .012f), "#294d43");
            }
        }
    }
    private void Cone(float x, float z)
    {
        var n = Group(x, z);
        B(n, new Vector3(0, .025f, 0), new Vector3(.36f, .05f, .36f), "#384442");
        C(n, new Vector3(0, .28f, 0), .145f, .5f, "#cf6b3b", .025f);
        C(n, new Vector3(0, .34f, 0), .09f, .085f, "#d9d3b3", .07f);
    }
    private void Car(float x, float z, float yaw, bool truck)
    {
        var n = Group(x, z, yaw);
        B(n, new Vector3(0, .45f, 0), new Vector3((truck ? 3.6f : 4.2f), .45f, 1.62f), "#e5e4d7", true);
        B(n, new Vector3(0, .3f, 0), new Vector3((truck ? 3.5f : 4.1f), .20f, 1.58f), "#283b3c");
        B(n, new Vector3((truck ? .52f : -.10f), 1.03f, 0), new Vector3(1.35f, .72f, 1.45f), "#506f78");
        B(n, new Vector3((truck ? .52f : -.10f), 1.44f, 0), new Vector3(1.50f, .13f, 1.54f), "#e3e3d5");
        foreach (var sx in new[] { -1, 1 })
        {
            B(n, new Vector3(((truck ? .52f : -.10f)) + sx * .68f, 1.03f, 0), new Vector3(.09f, .72f, 1.45f), "#e5e4d7");
            foreach (var side in new[] { -1, 1 })
            {
                var wheel = C(n, new Vector3(sx * 1.25f, .34f, side * .79f), .32f, .18f, "#293333");
                wheel.Rotation = new Vector3(Mathf.Pi / 2, 0, 0);
                var hub = C(n, new Vector3(sx * 1.25f, .34f, side * .89f), .17f, .025f, "#abb4ad");
                hub.Rotation = new Vector3(Mathf.Pi / 2, 0, 0);
            }
        }
        if (truck)
        {
            B(n, new Vector3(-1.05f, .73f, 0), new Vector3(1.4f, .12f, 1.6f), "#afb6ac");
            foreach (var side in new[] { -1, 1 })
            {
                B(n, new Vector3(-1.05f, .86f, side * .76f), new Vector3(1.5f, .28f, .09f), "#d1d5c7");
            }
        }
        else
        {
            B(n, new Vector3(1.30f, .78f, 0), new Vector3(1.4f, .25f, 1.59f), "#eceadd");
        }
        foreach (var side in new[] { -1, 1 })
        {
            B(n, new Vector3((truck ? 1.82f : 2.11f), .66f, side * .52f), new Vector3(.045f, .20f, .40f), "#e7e4bd");
            B(n, new Vector3((truck ? -1.82f : -2.11f), .66f, side * .52f), new Vector3(.045f, .17f, .34f), "#bd4738");
        }
        B(n, new Vector3((truck ? 1.84f : 2.14f), .46f, 0), new Vector3(.03f, .17f, .34f), "#d4c98b");
    }
    private void Bicycle(float x, float z, float yaw, string tint)
    {
        var n = Group(x, z, yaw);
        foreach (var sx in new[] { -.6f, .6f })
        {
            var torus = new TorusMesh();
            torus.InnerRadius = .30f;
            torus.OuterRadius = .34f;
            var wheel = new MeshInstance3D();
            wheel.Mesh = torus;
            wheel.MaterialOverride = M("#35433e");
            wheel.Position = new Vector3(sx, .36f, 0);
            wheel.Rotation = new Vector3(Mathf.Pi / 2, 0, 0);
            n.AddChild(wheel);
            for (int i = 0; i < 8; i += 1)
            {
                var a = i * Mathf.Tau / 8;
                Line(n, new Vector3(sx, .36f, 0), new Vector3(sx + Mathf.Cos(a) * .30f, .36f + Mathf.Sin(a) * .30f, 0), .005f, "#aeb7a4");
            }
        }
        foreach (var pair in new[] { new[] { new Vector3(-.6f, .36f, 0), new Vector3(-.2f, .8f, 0) }, new[] { new Vector3(-.2f, .8f, 0), new Vector3(.08f, .36f, 0) }, new[] { new Vector3(.08f, .36f, 0), new Vector3(-.6f, .36f, 0) }, new[] { new Vector3(-.2f, .8f, 0), new Vector3(.46f, .86f, 0) }, new[] { new Vector3(.46f, .86f, 0), new Vector3(.08f, .36f, 0) }, new[] { new Vector3(.46f, .86f, 0), new Vector3(.6f, .36f, 0) } })
        {
            Line(n, pair[0], pair[1], .022f, tint);
        }
        B(n, new Vector3(-.2f, .92f, 0), new Vector3(.28f, .07f, .17f), "#514d3d");
        Line(n, new Vector3(.46f, .86f, 0), new Vector3(.4f, 1.08f, 0), .025f, "#b7bdb0");
        Line(n, new Vector3(.4f, 1.08f, -.20f), new Vector3(.4f, 1.08f, .20f), .025f, "#b7bdb0");
    }
    private void Railway()
    {
        RailSigns();
        var controls = new[] { new Vector3(-80, 11.5f, 36), new Vector3(-52, 11.5f, 54), new Vector3(-44, 11.5f, 68), new Vector3(-40, 11.5f, 84), new Vector3(-20, 11.5f, 96), new Vector3(60, 11.5f, 96), new Vector3(108, 11.5f, 70) };
        // Catmull-Rom interpolation carries the railway through its control points
        // and preserves the pronounced western turn.
        for (int i = 0; i < controls.Length - 1; i += 1)
        {
            Vector3 a = controls[Math.Max(0, i - 1)];
            Vector3 q = controls[i];
            Vector3 d = controls[i + 1];
            Vector3 e = controls[Math.Min(controls.Length - 1, i + 2)];
            for (int j = 0; j < 8; j += 1)
            {
                var t = j / 8.0f;
                _track.AddPoint((.5f * ((2 * q) + (-a + d) * t + (2 * a - 5 * q + 4 * d - e) * t * t + (-a + 3 * q - 3 * d + e) * t * t * t)));
            }
        }
        _track.AddPoint(controls[^1]);
        _track.BakeInterval = .4f;
        var length = _track.GetBakedLength();
        var closest = float.PositiveInfinity;
        for (int i = 0; i < 401; i += 1)
        {
            var fraction = i / 400.0f;
            var point = _track.SampleBaked(fraction * length);
            var distance_to_start = new Vector2(point.X - 89, point.Z - TrackZ(89)).Length();
            if (distance_to_start < closest)
            {
                closest = distance_to_start;
                _trainStart = fraction;
            }
        }
        var distance = 0.0f;
        while (distance < length)
        {
            var a = _track.SampleBaked(distance);
            var q = _track.SampleBaked(Mathf.Min(distance + 2, length));
            var direction = (q - a).Normalized();
            var side = new Vector3(-direction.Z, 0, direction.X);
            var center = (a + q) * .5f;
            var bridge = center.X >= 12 && center.X <= 44;
            var segment = new Node3D();
            AddChild(segment);
            segment.Position = center;
            segment.Rotation = new Vector3(0, Mathf.Atan2(-direction.Z, direction.X), 0);
            if (!bridge)
            {
                B(segment, new Vector3(0, -.65f, 0), new Vector3(a.DistanceTo(q) + .04f, 1.3f, 8.5f), _finishes.Surface("concrete", "#b0aea0"));
            }
            else
            {
                B(segment, new Vector3(0, -.15f, 0), new Vector3(a.DistanceTo(q) + .04f, .3f, 4.5f), "#514c3c");
                B(segment, new Vector3(0, -.65f, 0), new Vector3(.3f, .75f, 8.2f), "#79573d");
            }
            foreach (var sz in new[] { -1, 1 })
            {
                if (!bridge)
                {
                    B(segment, new Vector3(0, .45f, sz * 4.06f), new Vector3(2.05f, .9f, .38f), "#cac9b7");
                    B(segment, new Vector3(0, -1.95f, sz * 1.9f), new Vector3(2.05f, .7f, .50f), "#9b9987");
                    B(segment, new Vector3(0, 1.38f, sz * 4.12f), new Vector3(.07f, 1.1f, .07f), "#e3e2d2");
                    foreach (var y in new[] { 1.4f, 1.9f })
                    {
                        B(segment, new Vector3(0, y, sz * 4.12f), new Vector3(2.05f, .04f, .04f), "#e3e2d2");
                    }
                }
                B(segment, new Vector3(0, .31f, sz * .83f), new Vector3(2.06f, .13f, .09f), "#5e655f");
            }
            for (int j = 0; j < 3; j += 1)
            {
                B(segment, new Vector3(-.7f + j * .7f, .17f, 0), new Vector3(.19f, .12f, 2.25f), "#6d7364");
            }
            if ((int)(distance / 2) % 6 == 0 && !bridge)
            {
                float ground = _world.HeightAt(center.X, center.Z);
                var ph = 11.5f - ground - 2.2f;
                if (ph > 1)
                {
                    B(segment, new Vector3(0, -2.2f - ph * .5f, 0), new Vector3(1.65f, ph, 4.9f), _finishes.Surface("concrete", "#a8a799"), true);
                    B(segment, new Vector3(0, -2.35f, 0), new Vector3(2.1f, .7f, 6.8f), "#c7c5b2");
                }
            }
            if ((int)(distance / 2) % 13 == 0)
            {
                foreach (var sz in new[] { -1, 1 })
                {
                    C(segment, new Vector3(0, 3.7f, sz * 3.05f), .07f, 7.4f, "#727c72");
                }
                B(segment, new Vector3(0, 7.3f, 0), new Vector3(.12f, .12f, 6.4f), "#757f74");
                foreach (var sz in new[] { -1, 1 })
                {
                    C(segment, new Vector3(0, 6.9f, sz * .8f), .07f, .6f, "#b8beb0");
                }
            }
            foreach (var sz in new[] { -.7f, .7f })
            {
                Line(this, a + side * sz + new Vector3(0, 6.6f, 0), q + side * sz + new Vector3(0, 6.6f, 0), .012f, "#54635b");
            }
            distance += 2.0f;
        }
        // Riveted steel through-truss spans the gully between x12 and x44.
        var start = new Vector3(12, 11.5f, TrackZ(12));
        var finish = new Vector3(44, 11.5f, TrackZ(44));
        var delta = finish - start;
        var trussSide = new Vector3(-delta.Z, 0, delta.X).Normalized() * 4.25f;
        foreach (var sign_value in new[] { -1, 1 })
        {
            Vector3 offset = trussSide * sign_value;
            Line(this, start + offset - new Vector3(0, .6f, 0), finish + offset - new Vector3(0, .6f, 0), .23f, "#79573d");
            Line(this, start.Lerp(finish, .125f) + offset + new Vector3(0, 9, 0), start.Lerp(finish, .875f) + offset + new Vector3(0, 9, 0), .23f, "#79573d");
            for (int i = 0; i < 8; i += 1)
            {
                var a = start.Lerp(finish, i / 8.0f) + offset;
                var q = start.Lerp(finish, (i + 1) / 8.0f) + offset;
                var low = a - new Vector3(0, .6f, 0);
                if (i > 0)
                {
                    Line(this, low, a + new Vector3(0, 9, 0), .14f, "#79573d");
                }
                if (i == 0)
                {
                    Line(this, low, q + new Vector3(0, 9, 0), .18f, "#79573d");
                }
                else if (i == 7)
                {
                    Line(this, a + new Vector3(0, 9, 0), q - new Vector3(0, .6f, 0), .18f, "#79573d");
                }
                else if (i < 4)
                {
                    Line(this, a + new Vector3(0, 9, 0), q - new Vector3(0, .6f, 0), .14f, "#79573d");
                }
                else
                {
                    Line(this, low, q + new Vector3(0, 9, 0), .14f, "#79573d");
                }
            }
        }
        for (int i = 1; i < 8; i += 1)
        {
            var a = start.Lerp(finish, i / 8.0f) + new Vector3(0, 9, 0);
            Line(this, a - trussSide, a + trussSide, .14f, "#79573d");
            if (i < 7)
            {
                var q = start.Lerp(finish, (i + 1) / 8.0f) + new Vector3(0, 9, 0);
                Line(this, a - trussSide, q + trussSide, .065f, "#79573d");
                Line(this, a + trussSide, q - trussSide, .065f, "#79573d");
            }
        }
        for (int i = 0; i < 4; i += 1)
        {
            var n = new Node3D();
            AddChild(n);
            _trainCars.Add(n);
            B(n, new Vector3(0, 2.604f, 0), new Vector3(19.5f, 2.808f, 2.9f), "#d6d8dc");
            B(n, new Vector3(0, 4.06f, 0), new Vector3(19.35f, .30f, 2.85f), "#b8bcc0");
            B(n, new Vector3(0, .95f, 0), new Vector3(18.5f, .50f, 2.46f), "#252f32");
            foreach (var sz in new[] { -1, 1 })
            {
                B(n, new Vector3(0, 3.1f, sz * 1.455f), new Vector3(19.45f, .96f, .025f), "#263b44");
                B(n, new Vector3(0, 2.1f, sz * 1.475f), new Vector3(19.45f, .24f, .025f), "#efc52c");
                for (int j = 0; j < 4; j += 1)
                {
                    float dx = -7.5f + j * 4.78f;
                    B(n, new Vector3(dx, 2.6f, sz * 1.48f), new Vector3(1.74f, 2.15f, .035f), "#bfc3c3");
                    foreach (var sx in new[] { -1, 1 })
                    {
                        B(n, new Vector3(dx + sx * .42f, 3.12f, sz * 1.505f), new Vector3(.65f, .80f, .025f), "#2b4148");
                    }
                    B(n, new Vector3(dx, 2.6f, sz * 1.51f), new Vector3(.025f, 2.15f, .015f), "#586561");
                }
                foreach (var sx in new[] { -6.5f, 6.5f })
                {
                    var wheel = C(n, new Vector3(sx, .43f, sz * .75f), .43f, .2f, "#26322f");
                    wheel.Rotation = new Vector3(Mathf.Pi / 2, 0, 0);
                    B(n, new Vector3(sx, .7f, sz * .9f), new Vector3(2.6f, .4f, .3f), "#26322f");
                }
            }
            foreach (var sx in new[] { -6, 0, 6 })
            {
                B(n, new Vector3(sx, 4.36f, 0), new Vector3(1.6f, .35f, 1.8f), "#c9cfcd");
            }
            foreach (var sx in new[] { -1, 1 })
            {
                B(n, new Vector3(sx * 9.76f, 3, 0), new Vector3(.13f, 1.8f, 2.61f), "#243337");
                B(n, new Vector3(sx * 9.84f, 1.81f, 0), new Vector3(.03f, .35f, 2.66f), "#efc52c");
                foreach (var sz in new[] { -1, 1 })
                {
                    B(n, new Vector3(sx * 9.86f, 3.43f, sz * .9f), new Vector3(.05f, .22f, .4f), "#f3eaca");
                }
            }
        }
        UpdateTrain();
    }
    private float TrackZ(float x)
    {
        for (int i = 0; i < _track.PointCount - 1; i += 1)
        {
            var a = _track.GetPointPosition(i);
            var q = _track.GetPointPosition(i + 1);
            if (x >= a.X && x <= q.X)
            {
                return Mathf.Lerp(a.Z, q.Z, (x - a.X) / (q.X - a.X));
            }
        }
        return 96.0f;
    }
    private void UpdateTrain()
    {
        var length = _track.GetBakedLength();
        var phase = Mathf.PosMod((_elapsed - 3.0f) / 70.0f, 1.0f);
        var fraction = (phase < .5f ? _trainStart - phase * 1.8f : _trainStart - .9f + (phase - .5f) * 1.8f);
        for (int i = 0; i < _trainCars.Count; i += 1)
        {
            var at = fraction * length - i * 20.3f;
            var n = _trainCars[i];
            n.Visible = at >= 0 && at <= length;
            if (!n.Visible)
            {
                continue;
            }
            var pos = _track.SampleBaked(at) + new Vector3(0, .5f, 0);
            var direction = _track.SampleBaked(Mathf.Min(length, at + .5f)) - _track.SampleBaked(Mathf.Max(0, at - .5f));
            n.Position = pos;
            n.Rotation = new Vector3(0, Mathf.Atan2(-direction.Z, direction.X), 0);
        }
    }
    public override void _Process(double delta)
    {
        float dt = (float)delta;
        Tick(dt);
    }
    private void Tick(float dt)
    {
        if (!OS.GetCmdlineUserArgs().Contains("--shot"))
        {
            _elapsed += dt;
        }
        if (!(_trainCars.Count == 0))
        {
            UpdateTrain();
        }
        foreach (var n in _butterflies)
        {
            Vector3 origin = n.GetMeta("origin").AsVector3();
            float phase = n.GetMeta("phase").AsSingle();
            var t = _elapsed * .8f + phase;
            n.Position = origin + new Vector3(Mathf.Sin(t * .7f) * .8f, Mathf.Sin(t * 1.9f) * .25f, Mathf.Cos(t * .55f) * .6f);
            n.Rotation = new Vector3(0, t * .7f, 0);
            n.GetChild<Node3D>(0).Rotation = new Vector3(0, 0, Mathf.Sin(_elapsed * 22 + phase) * .9f);
            n.GetChild<Node3D>(1).Rotation = new Vector3(0, 0, -Mathf.Sin(_elapsed * 22 + phase) * .9f);
        }
    }
    private void VillageUtilityYard()
    {
        Fence(new Vector2(-16, 72.6f), new Vector2(-11.8f, 72.6f), 1.95f, "#87958b", true);
        Fence(new Vector2(-11.8f, 72.6f), new Vector2(-6.4f, 72.6f), 1.95f, "#87958b", true);
        Fence(new Vector2(-6.4f, 72.6f), new Vector2(2, 72.6f), 2.5f, "#87958b", true);
        VendingMachine(-6.8f, 73.2f, .55f, "#b64b3a");
        var rack = Group(-9.7f, 73.1f, .08f);
        foreach (var xx in new[] { -.69f, .69f })
        {
            foreach (var zz in new[] { -.22f, .22f })
            {
                B(rack, new Vector3(xx, .925f, zz), new Vector3(.07f, 1.85f, .07f), "#5a4632");
            }
        }
        foreach (var yy in new[] { .07f, .925f, 1.8f })
        {
            B(rack, new Vector3(0, yy, 0), new Vector3(1.45f, .07f, .5f), "#816a49");
        }
        for (int i = 0; i < 6; i += 1)
        {
            foreach (var sz in new[] { -1, 1 })
            {
                B(rack, new Vector3(-.59f + i * .24f, .95f, sz * .25f), new Vector3(.1f, 1.63f, .045f), "#9d8158");
            }
        }
        var n = Group(-8.15f, 73.65f, .4f);
        for (int i = 0; i < 3; i += 1)
        {
            Crate(n, new Vector3(0, i * .33f, 0), new[] { "#7a5a3a", "#5a4d38", "#8a7a48" }[i]);
        }
        B(n, new Vector3(0, 1.16f, 0), new Vector3(.4f, .34f, .36f), "#b89d68");
        var pipe = Group(-6.2f, 73.55f);
        Line(pipe, new Vector3(0, .62f, 0), new Vector3(5.2f, .62f, 0), .11f, "#c3a743");
        foreach (var xx in new[] { .3f, 2.4f })
        {
            C(pipe, new Vector3(xx, .31f, 0), .04f, .62f, "#8e8980");
        }
        foreach (var xx in new[] { .675f, .925f })
        {
            var flange = C(pipe, new Vector3(xx, .62f, 0), .16f, .12f, "#2d4e4a");
            flange.Rotation = new Vector3(0, 0, Mathf.Pi / 2);
        }
        C(pipe, new Vector3(.8f, .82f, 0), .03f, .22f, "#8e8980");
        var torus = new TorusMesh();
        torus.InnerRadius = .10f;
        torus.OuterRadius = .14f;
        var valve = new MeshInstance3D();
        valve.Mesh = torus;
        valve.MaterialOverride = M("#b03a30");
        valve.Position = new Vector3(.8f, .95f, 0);
        pipe.AddChild(valve);
        for (int i = 0; i < 4; i += 1)
        {
            var yaw = i * Mathf.Pi / 2;
            Line(pipe, new Vector3(.8f, .95f, 0), new Vector3(.8f + Mathf.Cos(yaw) * .11f, .95f, Mathf.Sin(yaw) * .11f), .012f, "#b03a30");
        }
        var barricade = Group(-6.6f, 73.95f, .25f);
        foreach (var xx in new[] { -.6f, .6f })
        {
            foreach (var zz in new[] { -.12f, .12f })
            {
                Line(barricade, new Vector3(xx, 0, zz), new Vector3(xx, .85f, 0), .02f, "#bdc3b5");
            }
        }
        foreach (var yy in new[] { .42f, .78f })
        {
            B(barricade, new Vector3(0, yy, 0), new Vector3(1.3f, .18f, .04f), "#e4e3cc");
            for (int j = 0; j < 7; j += 1)
            {
                var stripe = B(barricade, new Vector3(-.57f + j * .18f, yy, .025f), new Vector3(.085f, .19f, .012f), "#d87545");
                stripe.Rotation = new Vector3(0, 0, -.35f);
            }
        }
    }
    private void ChainlinkPanel(Vector3 a, Vector3 q, float height)
    {
        var st = new SurfaceTool();
        st.Begin(Mesh.PrimitiveType.Triangles);
        var verts = new[] { a, q, q + new Vector3(0, height, 0), a, a + new Vector3(0, height, 0), q + new Vector3(0, height, 0) };
        var u = a.DistanceTo(q) * 6.5f;
        var v = height * 6.5f;
        var uv = new[] { new Vector2(0, 0), new Vector2(u, 0), new Vector2(u, v), new Vector2(0, 0), new Vector2(0, v), new Vector2(u, v) };
        for (int i = 0; i < 6; i += 1)
        {
            st.SetUV(uv[i]);
            st.AddVertex(verts[i]);
        }
        st.GenerateNormals();
        var inst = new MeshInstance3D();
        inst.Mesh = st.Commit();
        inst.MaterialOverride = _finishes.Chainlink();
        AddChild(inst);
    }
    private void PaddyGuardrail()
    {
        var previous = Vector3.Zero;
        var count = 0;
        var pts = _world.Roads[0];
        for (int i = 0; i < pts.Count - 1; i += 1)
        {
            Vector2 p = pts[i];
            if (p.X < 44 || p.Y < -6 || p.Y > 42)
            {
                continue;
            }
            Vector2 delta = (pts[i + 1] - p).Normalized();
            var at = p + new Vector2(delta.Y, -delta.X) * 4.45f;
            var v = new Vector3(at.X, _world.HeightAt(at.X, at.Y) + .595f, at.Y);
            if (count > 0 && previous.DistanceTo(v) < 5)
            {
                var rail = new Node3D();
                AddChild(rail);
                rail.Position = (previous + v) * .5f;
                rail.Rotation = new Vector3(0, Mathf.Atan2(-(v.Z - previous.Z), v.X - previous.X), 0);
                foreach (var off in new[] { -.105f, 0, .105f })
                {
                    B(rail, new Vector3(0, off, (off == 0 ? .012f : 0)), new Vector3(previous.DistanceTo(v) + .06f, .085f, .035f), "#8e9578");
                }
            }
            if (count % 2 == 0)
            {
                B(this, v - new Vector3(0, .30f, -.1f), new Vector3(.09f, .675f, .12f), "#7a8668");
            }
            previous = v;
            count += 1;
        }
    }
    private void RailSigns()
    {
        var x = 23.331f;
        var z = 84.129f;
        var n = Group(x, z, Mathf.Atan2(19.2f - x, 80 - z));
        float ground = _world.HeightAt(x, z);
        C(n, new Vector3(0, (10.78f - ground) * .5f, 0), .035f, 10.78f - ground, "#87918a");
        var sign_y = 7.39f - ground;
        var st = new SurfaceTool();
        st.Begin(Mesh.PrimitiveType.Triangles);
        Triangle(st, new Vector3(-.38f, .34f, .07f), new Vector3(.38f, .34f, .07f), new Vector3(0, -.34f, .07f));
        st.GenerateNormals();
        var triangle_mesh = new MeshInstance3D();
        triangle_mesh.Mesh = st.Commit();
        triangle_mesh.MaterialOverride = M("#e4ddd1");
        triangle_mesh.Position = new Vector3(triangle_mesh.Position.X, sign_y, triangle_mesh.Position.Z);
        n.AddChild(triangle_mesh);
        foreach (var pair in new[] { new[] { new Vector3(-.34f, .30f, .085f), new Vector3(.34f, .30f, .085f) }, new[] { new Vector3(.34f, .30f, .085f), new Vector3(0, -.30f, .085f) }, new[] { new Vector3(0, -.30f, .085f), new Vector3(-.34f, .30f, .085f) } })
        {
            Line(n, pair[0] + new Vector3(0, sign_y, 0), pair[1] + new Vector3(0, sign_y, 0), .035f, "#a43f30");
        }
        Label(n, "SLOW", new Vector3(0, sign_y + .04f, .092f), .085f, "#464b42");
        for (int j = 0; j < 2; j += 1)
        {
            var circle = C(n, new Vector3(0, sign_y - .71f - j * .66f, .07f), .29f, .035f, (j == 0 ? "#365c7d" : "#a44336"));
            circle.Rotation = new Vector3(Mathf.Pi / 2, 0, 0);
            if (j == 1)
            {
                var inner = C(n, new Vector3(0, sign_y - 1.37f, .095f), .225f, .02f, "#e1ddd1");
                inner.Rotation = new Vector3(Mathf.Pi / 2, 0, 0);
                B(n, new Vector3(0, sign_y - 1.40f, .11f), new Vector3(.27f, .095f, .014f), "#304969");
                B(n, new Vector3(-.035f, sign_y - 1.32f, .11f), new Vector3(.16f, .08f, .014f), "#304969");
                foreach (var sx in new[] { -1, 1 })
                {
                    var wheel = C(n, new Vector3(sx * .085f, sign_y - 1.46f, .12f), .024f, .012f, "#253e5e");
                    wheel.Rotation = new Vector3(Mathf.Pi / 2, 0, 0);
                }
                var slash = B(n, new Vector3(0, sign_y - 1.37f, .14f), new Vector3(.055f, .5f, .014f), "#aa483d");
                slash.Rotation = new Vector3(0, 0, -.78f);
            }
            else
            {
                B(n, new Vector3(-.04f, sign_y - .71f, .10f), new Vector3(.06f, .34f, .016f), "#e3dfc9");
                B(n, new Vector3(.055f, sign_y - .73f, .10f), new Vector3(.24f, .055f, .016f), "#e3dfc9");
                foreach (var sx in new[] { -1, 1 })
                {
                    var arrow = B(n, new Vector3(-.04f + sx * .046f, sign_y - .59f, .10f), new Vector3(.045f, .13f, .016f), "#e3dfc9");
                    arrow.Rotation = new Vector3(0, 0, sx * .75f);
                    var turn_arrow = B(n, new Vector3(.13f, sign_y - .73f + sx * .045f, .11f), new Vector3(.045f, .13f, .016f), "#e3dfc9");
                    turn_arrow.Rotation = new Vector3(0, 0, Mathf.Pi * .5f + sx * .75f);
                }
            }
        }
    }
    private void ShrineGable(Node3D n)
    {
        foreach (var sz in new[] { -1, 1 })
        {
            var st = new SurfaceTool();
            st.Begin(Mesh.PrimitiveType.Triangles);
            foreach (var sx in new[] { -1, 1 })
            {
                var previous = new Vector3(sx * 2.48f, 4.448f, sz * 2.65f);
                for (int j = 1; j < 13; j += 1)
                {
                    var t = j / 12.0f;
                    var next = new Vector3(sx * 2.48f * (1 - t), 3.95f + 2.392f * (Mathf.Pow(t, 1.55f) + .3f * (1 - t)) - .22f, sz * 2.65f);
                    Triangle(st, new Vector3(0, 3.55f, sz * 2.65f), previous, next);
                    Line(n, previous + new Vector3(0, .14f, sz * .10f), next + new Vector3(0, .14f, sz * .10f), .105f, "#252b2b");
                    previous = next;
                }
            }
            st.GenerateNormals();
            var face = new MeshInstance3D();
            face.Mesh = st.Commit();
            var mat = _finishes.Surface("wood", "#c1b691");
            mat.CullMode = BaseMaterial3D.CullModeEnum.Disabled;
            face.MaterialOverride = mat;
            n.AddChild(face);
        }
    }
    private Vector3 RoofPoint(float half, float ridge, float depth, float rise, float curved, float side, float t, float u, bool hip)
    {
        var x = Mathf.Lerp(half, ridge, t) * u;
        var y = rise * t;
        var z = side * (1 - t) * depth * .5f;
        if (!hip && curved > 1.2f)
        {
            y = rise * (Mathf.Pow(t, 1.55f) + (1 - t) * .55f * Mathf.Pow(Mathf.Abs(u), 3));
            z *= 1 + .06f * Mathf.Pow(Mathf.Abs(u), 3);
        }
        else if (!hip && curved > 0)
        {
            y = rise * Mathf.Pow(t, 1 + .8f * curved) + (1 - t) * .22f * curved * Mathf.Pow(Mathf.Abs(u), 4) * rise;
        }
        return new Vector3(x, y, z);
    }
    private void HazardTape(Vector3 a, Vector3 q, float height)
    {
        var count = Math.Max(2, (int)(a.DistanceTo(q) / .11f));
        for (int i = 0; i < count; i += 1)
        {
            var t0 = (float)(i) / count;
            var t1 = (float)(i + 1) / count;
            var p = a.Lerp(q, t0) - new Vector3(0, .32f * t0 * (1 - t0), 0);
            var end = a.Lerp(q, t1) - new Vector3(0, .32f * t1 * (1 - t1), 0);
            var tape = B(this, (p + end) * .5f, new Vector3(p.DistanceTo(end) + .003f, height, .009f), (i % 2 == 0 ? "#c8b64a" : "#333e36"));
            tape.Rotation = new Vector3(0, Mathf.Atan2(-(end.Z - p.Z), end.X - p.X), 0);
        }
    }
    private void ViaductVending()
    {
        var n = Group(-63.09f, 60.16f, -1.95f);
        B(n, new Vector3(0, .5f, 0), new Vector3(3, 1, 1.9f), "#8d8982", true);
        var machine = VendingMachine(-62.933f, 59.898f, -2.25f, "#b6443b", true);
        machine.Position = new Vector3(machine.Position.X, machine.Position.Y + 1, machine.Position.Z);
        var points = new List<Vector2>();
        foreach (var v in new[] { new Vector2(5.2f, -1.8f), new Vector2(3.8f, 1.2f), new Vector2(2.9f, 3.6f) })
        {
            points.Add(new Vector2(-64.3f + .929f * v.X - .370f * v.Y, 58.6f + .370f * v.X + .929f * v.Y));
        }
        Fence(points[0], points[1], 3, "#657e76", true);
        Fence(points[1], points[2], 3, "#657e76", true);
        var crate_pos = new Vector2(-64.3f + .929f * 1.5f - .370f * 1.4f, 58.6f + .370f * 1.5f + .929f * 1.4f);
        var crate_group = Group(crate_pos.X, crate_pos.Y, -1.7f);
        Crate(crate_group, new Vector3(0, 1, 0), "#3a8a4a");
    }
    private void Stonework(Node3D parent, float width, float depth, float height, float bottom)
    {
        var random = new RandomNumberGenerator();
        random.Seed = 351;
        for (int side = 0; side < 4; side += 1)
        {
            var n = new Node3D();
            parent.AddChild(n);
            n.Rotation = new Vector3(0, side * Mathf.Pi / 2, 0);
            var length = (side % 2 == 0 ? width : depth);
            var distance = (side % 2 == 0 ? depth * .5f : width * .5f);
            for (int row = 0; row < Math.Max(1, (int)(height / .35f)); row += 1)
            {
                float x = -length * .5f - .2f;
                while (x < length * .5f)
                {
                    var sw = random.RandfRange(.3f, .65f);
                    var y = bottom + row * .35f + random.RandfRange(-.04f, .04f);
                    var st = new SurfaceTool();
                    st.Begin(Mesh.PrimitiveType.Triangles);
                    var verts = new[] { new Vector3(x, y + .1f, distance + .012f), new Vector3(x + sw * .28f, y + .02f, distance + .012f), new Vector3(Mathf.Min(length * .5f, x + sw * .95f), y + .06f, distance + .012f), new Vector3(Mathf.Min(length * .5f, x + sw * .87f), y + .31f, distance + .012f), new Vector3(x + sw * .17f, y + .32f, distance + .012f) };
                    for (int j = 1; j < 4; j += 1)
                    {
                        Triangle(st, verts[0], verts[j], verts[j + 1]);
                    }
                    st.GenerateNormals();
                    var stone = new MeshInstance3D();
                    stone.Mesh = st.Commit();
                    stone.MaterialOverride = M(new[] { "#8d826a", "#a09479", "#746e59", "#9b8f75" }[random.RandiRange(0, 3)]);
                    n.AddChild(stone);
                    x += sw;
                }
            }
        }
    }
}
