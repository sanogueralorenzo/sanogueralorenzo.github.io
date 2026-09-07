using Godot;

namespace CozySora;

public sealed class HarborNature
{
    private HarborWorld _map = null!;
    private HarborGeometry _g = null!;
    private readonly RandomNumberGenerator _rng = new();
    private int _treeCount;
    public void Build(HarborWorld world, HarborGeometry geometry)
    {
        _map = world;
        _g = geometry;
        _rng.Seed = 44391;
        // A contiguous wooded park on the western hill, with deliberate sightlines to the bay.
        for (int i = 0; i < 120; i += 1)
        {
            var x = _rng.RandfRange(-166, -87);
            var z = _rng.RandfRange(-30, 163);
            if (Mathf.Abs(x + 104) < 5 && z > 43 && z < 98)
            {
                continue;
            }
            if (new Vector2(x + 109, z - 96).Length() < 16)
            {
                continue;
            }
            Cypress(_map.Point(x, z), _rng.RandfRange(5.5f, 12), i);
        }
        // The upper park continues to the stair landings, framing several open glades.
        for (int i = 0; i < 100; i += 1)
        {
            var x = _rng.RandfRange(-91, -18);
            var z = _rng.RandfRange(57, 162);
            if (Mathf.Abs(x + 38) < 5 && z < 98)
            {
                continue;
            }
            if (new Vector2(x + 56, z - 62).Length() < 11)
            {
                continue;
            }
            if (new Vector2(x + 54, z - 110).Length() < 15)
            {
                continue;
            }
            if (OnPath(x, z, 4))
            {
                continue;
            }
            Cypress(_map.Point(x, z), _rng.RandfRange(5.5f, 10), i + 300);
        }
        // Taller rounded street crowns cast broken shade over the pavement.
        foreach (var x in new[] { -.6f, 17.0f })
        {
            foreach (var z in new[] { -92.0f, -49.0f, -18.0f, 28.0f, 66.0f, 120.0f })
            {
                StreetTree(_map.Point(x, z), _rng.RandfRange(6.2f, 8.0f));
            }
        }
        foreach (var z in new[] { -74f, -57f, -12f, 24f, 70f })
        {
            StreetTree(_map.Point(12.65f, z), _rng.RandfRange(6.2f, 7.5f));
        }
        foreach (var x in new[] { -65.0f, -35.0f, 38.0f, 67.0f, 114.0f })
        {
            foreach (var z in new[] { -110.0f, -39.0f, 53.0f })
            {
                if (z == 53.0f && x < 0)
                {
                    continue;
                }
                StreetTree(_map.Point(x, z), _rng.RandfRange(5.2f, 7.2f));
            }
        }
        GD.Print("Harbor Hills park and street trees: ", _treeCount);
        foreach (var route in new[] { new[] { new Vector2(-112, 101), new Vector2(-54, 110) }, new[] { new Vector2(-104, 74), new Vector2(-22, 111) }, new[] { new Vector2(-55, 110), new Vector2(-16, 133) } })
        {
            var path = new List<Vector3>();
            for (int i = 0; i < 42; i += 1)
            {
                Vector2 p = route[0].Lerp(route[1], i / 41.0f);
                path.Add(_map.Point(p.X, p.Y, .08f));
            }
            _g.Ribbon(path, 3.0f, "aca98c", true);
        }
        for (int i = 0; i < 360; i += 1)
        {
            var x = _rng.RandfRange(-91, -18);
            var z = _rng.RandfRange(54, 168);
            if (Mathf.Abs(x + 38) < 3 && z < 98)
            {
                continue;
            }
            if (OnPath(x, z, 2))
            {
                continue;
            }
            var p = _map.Point(x, z);
            _g.Add("leaf", p + new Vector3(0, .45f, 0), new Vector3(1.5f, .9f, 1.4f), new[] { "758959", "657c58", "949a69" }[i % 3]);
            for (int j = 0; j < 3; j += 1)
            {
                var at = p + new Vector3(_rng.RandfRange(-.4f, .4f), .9f, _rng.RandfRange(-.4f, .4f));
                if (!_map.RoadEndContains(at.X, at.Z, .4f))
                {
                    _g.Add("sphere", at, new Vector3(.13f, .12f, .13f), "d2bb7c");
                }
            }
        }
        // Street trees fit the planting strip, never a doorway or the rail alignment.
        foreach (var x in new[] { -85.0f, 99.0f })
        {
            for (int z = -82; z < 130; z += 19)
            {
                Cypress(_map.Point(x, z), _rng.RandfRange(4.5f, 6.0f), z);
            }
        }
        for (int x = -152; x < 163; x += 19)
        {
            if (Mathf.Abs(x - 8) < 10)
            {
                continue;
            }
            Cypress(_map.Point(x, -107), _rng.RandfRange(4.2f, 6.4f), x);
        }
        for (int i = 0; i < 35; i += 1)
        {
            var x = _rng.RandfRange(132, 171);
            var z = _rng.RandfRange(-73, 164);
            Cypress(_map.Point(x, z), _rng.RandfRange(6, 10), i);
        }
        foreach (var x in new[] { 31.0f, 53.0f, 75.0f })
        {
            foreach (var z in new[] { 128.0f, 154.0f })
            {
                StreetTree(_map.Point(x, z), _rng.RandfRange(6.2f, 8.2f));
            }
        }
        // Perimeter scrub and wildflowers establish a finished edge rather than an empty plane.
        for (int i = 0; i < 1500; i += 1)
        {
            var x = _rng.RandfRange(-173, 173);
            var z = _rng.RandfRange(-107, 171);
            if (x > -83 && x < 128 && z < 136)
            {
                continue;
            }
            if ((Mathf.Abs(x + 104) < 3 || Mathf.Abs(x + 38) < 3) && z > 44 && z < 95)
            {
                continue;
            }
            var p = _map.Point(x, z);
            _g.Add("leaf", p + new Vector3(0, .3f, 0), new Vector3(_rng.RandfRange(.6f, 1.5f), _rng.RandfRange(.55f, 1.3f), _rng.RandfRange(.6f, 1.5f)), new[] { "677f5a", "89946a", "55765b", "9b9c6e" }[i % 4]);
            if (i % 3 == 0)
            {
                for (int j = 0; j < 4; j += 1)
                {
                    var at = (p + new Vector3(_rng.RandfRange(-.5f, .5f), .6f + _rng.Randf() * .3f, _rng.RandfRange(-.5f, .5f)));
                    if (!_map.RoadEndContains(at.X, at.Z, .4f))
                    {
                        _g.Add("sphere", at, new Vector3(.12f, .12f, .12f), new[] { "d3bf80", "b9979c", "ddd3a8" }[i % 3]);
                    }
                }
            }
        }
        // A composed overlook with a low wall, relief plaque and warm stone terraces.
        var overlook = _map.Point(-110, 99);
        _g.Add("cylinder", overlook - new Vector3(0, .12f, 0), new Vector3(21, .3f, 17), "b3ae93", Vector3.Zero, true);
        for (int i = 0; i < 25; i += 1)
        {
            var angle = Mathf.Pi * .12f + i / 24.0f * Mathf.Pi * .77f;
            var a = overlook + new Vector3(Mathf.Sin(angle) * 10, 0, Mathf.Cos(angle) * 8);
            _g.Box(a + new Vector3(0, .5f, 0), new Vector3(.9f, 1.0f, 1), "969c8b", true, angle);
        }
        _g.Box(overlook + new Vector3(-3, .85f, -3), new Vector3(2.8f, .16f, 1), "627c71", false, 0);
        _g.Label("THE LONG WAY HOME\nHARBOR HILLS OVERLOOK", overlook + new Vector3(-3, .98f, -2.45f), 2.3f, "e5d8b5", 0, 52);
        for (int i = 0; i < 4; i += 1)
        {
            _g.Add("leaf", overlook + new Vector3(-8 + i * .6f, .6f, -5), new Vector3(1.1f, 1.1f, 1.1f), "879666");
        }
        SkylineAndBridge();
        Boats();
        Grass();
    }
    private void Cypress(Vector3 p, float h, int index)
    {
        var clear = !_map.RoadEndContains(p.X, p.Z, 1.0f);
        if (clear)
        {
            _treeCount += 1;
        }
        var lean = new Vector3(-h * (.075f + .065f * Mathf.Sin(index * 1.7f)), 0, h * .06f * Mathf.Cos(index * 2.3f));
        if (clear)
        {
            _g.Branch(p, p + lean * .45f + new Vector3(0, h * .48f, 0), h * .035f, "827058");
            _g.Branch(p + lean * .45f + new Vector3(0, h * .48f, 0), p + lean + new Vector3(0, h * .91f, 0), h * .024f, "827058");
        }
        for (int i = 0; i < 5; i += 1)
        {
            var phase = i * 2.39f + index * .38f;
            var spread = h * (.21f - i * .026f);
            var tip = (p + new Vector3(Mathf.Cos(phase) * spread, h * (.43f + i * .12f + .024f * Mathf.Sin(phase)), Mathf.Sin(phase) * spread) + lean);
            if (clear)
            {
                _g.Branch(p + new Vector3(0, h * (.35f + i * .09f), 0) + lean * .6f, tip, h * .018f, "827058");
            }
            for (int j = 0; j < 12; j += 1)
            {
                var a = _rng.Randf() * Mathf.Tau;
                var r = Mathf.Sqrt(_rng.Randf()) * h * .19f;
                var at = tip + new Vector3(Mathf.Cos(a) * r, _rng.RandfRange(-.3f, .3f) * h * .29f, Mathf.Sin(a) * r);
                var size = _rng.RandfRange(.65f, 1.25f) * h * .22f;
                var rotation = new Vector3(0, a, _rng.RandfRange(-.1f, .1f));
                if (clear)
                {
                    _g.Add("leaf", at, new Vector3(size * 1.15f, size * 1.18f, size), new[] { "416c42", "557c45", "365e46", "6b874e" }[j % 4], rotation);
                }
            }
        }
    }
    private void SkylineAndBridge()
    {
        // Distant fictional city blocks remain outside the playable 360 m district.
        // The far shore grounds the skyline in a continuous muted land silhouette.
        _g.Add("sphere", new Vector3(350, -3, -336), new Vector3(550, 25, 90), "637f86");
        foreach (var center in new[] { -384.0f, -121.0f })
        {
            var st = new SurfaceTool();
            st.Begin(Mesh.PrimitiveType.Triangles);
            for (int ix = 0; ix < 28; ix += 1)
            {
                for (int iz = 0; iz < 36; iz += 1)
                {
                    var positions = new List<Vector3>();
                    foreach (var offset in new[] { new Vector2(0, 0), new Vector2(1, 0), new Vector2(1, 1), new Vector2(0, 1) })
                    {
                        var x = center - 84 + (ix + offset.X) * 6;
                        var z = -498 + (iz + offset.Y) * 6;
                        var slope = Mathf.Sin(Mathf.Clamp((x - center + 84) / 168.0f, 0, 1) * Mathf.Pi);
                        var y = -3 + 37 * slope * Mathf.SmoothStep(-280, -360, z);
                        positions.Add(new Vector3(x, y, z));
                    }
                    foreach (var j in new[] { 0, 1, 2, 0, 2, 3 })
                    {
                        st.AddVertex(positions[j]);
                    }
                }
            }
            st.GenerateNormals();
            var n = new MeshInstance3D();
            n.Mesh = st.Commit();
            n.MaterialOverride = _g.Material("788f92");
            _g.Root.AddChild(n);
        }
        for (int i = 0; i < 65; i += 1)
        {
            var x = 180 + i * 5.8f;
            var z = -310 + _rng.RandfRange(-20, 20);
            var h = _rng.RandfRange(9, 43);
            if (i % 13 == 0)
            {
                h *= 1.5f;
            }
            _g.Box(new Vector3(x, h * .5f - 1, z), new Vector3(_rng.RandfRange(4, 8), h, 7), new[] { "687f89", "7b9298", "576f7b" }[i % 3]);
            if (i % 6 == 0)
            {
                _g.Box(new Vector3(x, h + 1, z), new Vector3(2, 2, 3), "91a4a7");
            }
        }
        // A red suspension bridge silhouette, deliberately fictional in its proportions.
        var bridgeZ = -315.0f;
        var left = -365.0f;
        var right = -135.0f;
        _g.Box(new Vector3((left + right) * .5f, 16, bridgeZ), new Vector3(right - left, .9f, 8), "986f61");
        foreach (var x in new[] { -310.0f, -195.0f })
        {
            foreach (var side in new[] { -1, 1 })
            {
                _g.Box(new Vector3(x, 28, bridgeZ + side * 3.8f), new Vector3(2.6f, 60, 2.6f), "a77e6c");
            }
            foreach (var y in new[] { 21.0f, 38.0f, 54.0f })
            {
                _g.Box(new Vector3(x, y, bridgeZ), new Vector3(2.5f, 1.5f, 10), "a77e6c");
            }
        }
        foreach (var side in new[] { -1, 1 })
        {
            foreach (var section in new[] { new[] { left, -310.0f }, new[] { -310.0f, -195.0f }, new[] { -195.0f, right } })
            {
                var prev = Vector3.Zero;
                for (int i = 0; i < 33; i += 1)
                {
                    var t = i / 32.0f;
                    var x = Mathf.Lerp(section[0], section[1], t);
                    var height = 55 - 33 * Mathf.Sin(t * Mathf.Pi);
                    if (section[0] == left)
                    {
                        height = Mathf.Lerp(18, 55, t);
                    }
                    if (section[1] == right)
                    {
                        height = Mathf.Lerp(55, 18, t);
                    }
                    var at = new Vector3(x, height, bridgeZ + side * 4);
                    if (i > 0)
                    {
                        _g.Beam(prev, at, .18f, "a78779");
                    }
                    if (i % 2 == 0)
                    {
                        _g.Beam(new Vector3(x, 16, bridgeZ + side * 4), at, .055f, "a78779");
                    }
                    prev = at;
                }
            }
        }
    }
    private void Boats()
    {
        for (int i = 0; i < 14; i += 1)
        {
            var p = new Vector3(-130 + i * 22, -.35f, -151 - _rng.Randf() * 70);
            if (i == 0)
            {
                p = new Vector3(-123.7f, -.35f, -143);
            }
            var boat = new Node3D { Name = "MooredBoat" + i, Position = p };
            boat.SetMeta("water_float", true);
            _g.Root.AddChild(boat);
            var boatGeometry = new HarborGeometry(boat);
            p = Vector3.Zero;
            var yaw = _rng.RandfRange(-.35f, .35f);
            var st = new SurfaceTool();
            st.Begin(Mesh.PrimitiveType.Triangles);
            var sections = new[] { new Vector3(0, .18f, -3.9f), new Vector3(.82f, -.34f, -2.3f), new Vector3(1.12f, -.5f, 0), new Vector3(.94f, -.4f, 2.4f), new Vector3(.76f, -.2f, 3.1f) };
            for (int j = 0; j < sections.Length - 1; j += 1)
            {
                foreach (var side in new[] { -1, 1 })
                {
                    Vector3 a = sections[j];
                    Vector3 b = sections[j + 1];
                    var ring_a = new[] { new Vector3(a.X * side, .55f, a.Z), new Vector3(a.X * .72f * side, -.07f, a.Z), new Vector3(0, a.Y, a.Z) };
                    var ring_b = new[] { new Vector3(b.X * side, .55f, b.Z), new Vector3(b.X * .72f * side, -.07f, b.Z), new Vector3(0, b.Y, b.Z) };
                    for (int band = 0; band < 2; band += 1)
                    {
                        foreach (var v in new[] { ring_a[band], ring_b[band], ring_b[band + 1], ring_a[band], ring_b[band + 1], ring_a[band + 1] })
                        {
                            st.AddVertex(v);
                        }
                    }
                }
            }
            st.GenerateNormals();
            var n = new MeshInstance3D();
            n.Mesh = st.Commit();
            n.Position = p;
            n.Rotation = new Vector3(0, yaw, 0);
            var mat = new StandardMaterial3D();
            mat.AlbedoColor = new Color(new[] { "d8d9bf", "72958b", "b56d50" }[i % 3]);
            mat.CullMode = BaseMaterial3D.CullModeEnum.Disabled;
            n.MaterialOverride = mat;
            boatGeometry.Root.AddChild(n);
            var turn = new Basis(Vector3.Up, yaw);
            boatGeometry.Box(p + turn * new Vector3(0, .32f, .2f), new Vector3(1.55f, .12f, 5.1f), "9c896a", false, yaw);
            boatGeometry.Box(p + turn * new Vector3(0, .76f, -.7f), new Vector3(1.45f, .82f, 2.2f), "ded7b9", false, yaw);
            boatGeometry.Box(p + turn * new Vector3(0, .9f, -1.83f), new Vector3(1.2f, .35f, .035f), "537f89", false, yaw);
            foreach (var side in new[] { -1, 1 })
            {
                var previous = p + turn * new Vector3(0, .62f, -3.9f);
                foreach (var section in sections.Skip(1))
                {
                    var next = p + turn * new Vector3(section.X * side, .62f, section.Z);
                    boatGeometry.Beam(previous, next, .045f, "d3c39e");
                    previous = next;
                }
                boatGeometry.Box(p + turn * new Vector3(side * .92f, .62f, 1.65f), new Vector3(.22f, .18f, 2.1f), "c6b291", false, yaw);
            }
            if (i % 2 == 0)
            {
                boatGeometry.Beam(p + turn * new Vector3(0, .4f, -.8f), p + turn * new Vector3(0, 8.9f, -.8f), .046f, "b3b6a0");
                boatGeometry.Beam(p + turn * new Vector3(0, 1.7f, -.8f), p + turn * new Vector3(0, 1.7f, 2.8f), .035f, "b3b6a0");
                var sail = new SurfaceTool();
                sail.Begin(Mesh.PrimitiveType.Triangles);
                for (int row = 0; row < 12; row += 1)
                {
                    var t = row / 12f;
                    var t1 = (row + 1) / 12f;
                    var corners = new[] { new Vector3(.07f, 1.8f + t * 6.8f, -.8f), new Vector3(.07f + Mathf.Sin(t * Mathf.Pi) * .24f, 1.8f + t * 6.8f, 2.6f - t * 3.4f), new Vector3(.07f + Mathf.Sin(t1 * Mathf.Pi) * .24f, 1.8f + t1 * 6.8f, 2.6f - t1 * 3.4f), new Vector3(.07f, 1.8f + t1 * 6.8f, -.8f) };
                    foreach (var j in new[] { 0, 1, 2, 0, 2, 3 })
                    {
                        sail.AddVertex(corners[j]);
                    }
                }
                sail.GenerateNormals();
                n = new MeshInstance3D();
                n.Mesh = sail.Commit();
                n.Position = p;
                n.Rotation = new Vector3(0, yaw, 0);
                mat = new StandardMaterial3D();
                mat.AlbedoColor = new Color("e6dfc4");
                mat.CullMode = BaseMaterial3D.CullModeEnum.Disabled;
                n.MaterialOverride = mat;
                boatGeometry.Root.AddChild(n);
                boatGeometry.Beam(p + turn * new Vector3(0, 8.8f, -.8f), p + turn * new Vector3(0, .6f, -3.8f), .011f, "a6afa6");
            }
            // The mooring buoy remains a separate floating object.
            var buoy = new Node3D { Name = "MooringBuoy" + i, Position = boat.Position + new Vector3(3, -.45f, 2) };
            buoy.SetMeta("water_float", true);
            buoy.SetMeta("water_offset", .08f);
            _g.Root.AddChild(buoy);
            var buoyGeometry = new HarborGeometry(buoy);
            buoyGeometry.Add("sphere", Vector3.Zero, new Vector3(.4f, .5f, .4f), "ce9472");
            buoyGeometry.Finish();
            boatGeometry.Finish();
        }
    }
    private void Grass()
    {
        var st = new SurfaceTool();
        st.Begin(Mesh.PrimitiveType.Triangles);
        for (int i = 0; i < 5; i += 1)
        {
            st.SetColor(new Color(1f - i * .045f, 1f - i * .025f, 1f - i * .035f));
            var angle = i * 2.399f;
            var turn = new Basis(Vector3.Up, angle);
            var h = .52f + (i % 3) * .13f;
            var a = new Vector3(-.063f, 0, 0);
            var b = new Vector3(.063f, 0, 0);
            var c = new Vector3(-.039f, h * .6f, .14f);
            var d = new Vector3(.039f, h * .6f, .14f);
            var tip = new Vector3(.08f, h, .32f);
            foreach (var v in new[] { a, b, c, b, d, c, c, d, tip })
            {
                st.SetUV(new Vector2(0, v.Y / h));
                st.AddVertex(turn * v);
            }
        }
        st.GenerateNormals();
        var blade = st.Commit();
        var positions = new List<Transform3D>();
        for (int i = 0; i < 700000; i += 1)
        {
            var x = _rng.RandfRange(-172, 172);
            var z = _rng.RandfRange(-106, 170);
            var core = x > -87 && x < 131 && z < 136 && !(x < -18 && z > 53);
            var verge = ((z > 53 && z < 59 && x > -17 && x < 79) || (z > 40.5f && z < 44.0f && x > -69 && x < 81) || (z > 111 && z < 135 && x > 23 && x < 81));
            if (core && !verge)
            {
                continue;
            }
            var paved = false;
            foreach (var road_x in HarborWorld.StreetsX)
            {
                if (Mathf.Abs(x - road_x) < 8.5f && z < 136)
                {
                    paved = true;
                }
            }
            foreach (var road_z in HarborWorld.StreetsZ)
            {
                if (Mathf.Abs(z - road_z) < 8.5f && x > -121 && x < 130)
                {
                    paved = true;
                }
            }
            if (paved)
            {
                continue;
            }
            if (Mathf.Abs(_map.HeightAt(x, z) - _map.TerrainHeight(x, z)) > .1f)
            {
                continue;
            }
            if ((Mathf.Abs(x + 104) < 3 || Mathf.Abs(x + 38) < 3) && z > 44 && z < 95)
            {
                continue;
            }
            if (Mathf.Abs(x + 147 - Mathf.Sin(z * .018f) * 9) < 2.5f || Mathf.Abs(x - 151 - Mathf.Sin(z * .018f) * 9) < 2.5f)
            {
                continue;
            }
            if (new Vector2(x + 110, z - 99).Length() < 12 || new Vector2(x + 56, z - 62).Length() < 9)
            {
                continue;
            }
            if (OnPath(x, z, 2))
            {
                continue;
            }
            var transform = new Transform3D(new Basis(Vector3.Up, _rng.Randf() * Mathf.Tau).Scaled(Vector3.One * _rng.RandfRange(.55f, 1.3f)), _map.Point(x, z));
            if (!_map.RoadEndContains(x, z, .45f))
            {
                positions.Add(transform);
            }
        }
        var material = new ShaderMaterial();
        material.Shader = GD.Load<Shader>("res://shaders/grass.gdshader");
        material.SetShaderParameter("grass_base", new Vector3(.18f, .29f, .12f));
        material.SetShaderParameter("grass_mid", new Vector3(.32f, .43f, .18f));
        material.SetShaderParameter("grass_tip", new Vector3(.54f, .55f, .29f));
        var batch_count = CozyMeshBatches.Spatial(_g.Root, blade, material, positions, "Wind grass", 32, 110, 12, GeometryInstance3D.ShadowCastingSetting.Off);
        GD.Print("Harbor Hills vegetation: ", _treeCount, " cypress, ", positions.Count, " grass clumps in ", batch_count, " batches");
    }
    private bool OnPath(float x, float z, float width)
    {
        var p = new Vector2(x, z);
        foreach (var route in new[] { new[] { new Vector2(-112, 101), new Vector2(-54, 110) }, new[] { new Vector2(-104, 74), new Vector2(-22, 111) }, new[] { new Vector2(-55, 110), new Vector2(-16, 133) } })
        {
            Vector2 a = route[0];
            Vector2 b = route[1];
            var line = b - a;
            if ((p.DistanceTo(a + line * Mathf.Clamp((p - a).Dot(line) / line.LengthSquared(), 0, 1)) < width))
            {
                return true;
            }
        }
        return false;
    }
    private void StreetTree(Vector3 p, float h)
    {
        var clear = !_map.RoadEndContains(p.X, p.Z, 1.0f);
        if (clear)
        {
            _treeCount += 1;
        }
        if (clear)
        {
            _g.Branch(p, p + new Vector3(.12f, h * .4f, -.08f), .16f, "827058");
            _g.Branch(p + new Vector3(.12f, h * .4f, -.08f), p + new Vector3(.35f, h * .78f, -.15f), .11f, "827058");
        }
        for (int branch = 0; branch < 5; branch += 1)
        {
            var angle = branch * 2.399f;
            var tip = p + new Vector3(Mathf.Cos(angle) * 1.2f, h * (.7f + _rng.Randf() * .18f), Mathf.Sin(angle) * 1.2f);
            if (clear)
            {
                var origin = p + new Vector3(.12f, h * (.39f + branch * .045f), -.08f);
                var elbow = origin.Lerp(tip, .55f) + new Vector3(0, .24f, 0);
                _g.Branch(origin, elbow, .075f, "827058");
                _g.Branch(elbow, tip, .045f, "827058");
            }
            for (int j = 0; j < 9; j += 1)
            {
                var a = _rng.Randf() * Mathf.Tau;
                var r = Mathf.Sqrt(_rng.Randf()) * 1.2f;
                var at = tip + new Vector3(Mathf.Cos(a) * r, _rng.RandfRange(-.6f, .8f), Mathf.Sin(a) * r);
                if (clear)
                {
                    _g.Add("leaf", at, new Vector3(1.6f, 1.8f, 1.6f), new[] { "628641", "487740", "789448", "3c7148" }[j % 4], new Vector3(0, a, 0));
                }
            }
        }
    }
}
