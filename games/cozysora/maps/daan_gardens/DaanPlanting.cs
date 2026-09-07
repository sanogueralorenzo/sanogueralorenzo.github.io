using Godot;

namespace CozySora;

/// <summary>Seeded evergreen crowns, banyan roots and layered pond habitat.</summary>
public sealed class DaanPlanting
{
    private DaanWorld _map = null!;
    private DaanGeometry _g = null!;
    private readonly RandomNumberGenerator _rng = new();
    private readonly List<Transform3D>[] _leafGroups = [new(), new(), new(), new()];
    private readonly List<Vector2> _treePositions = new();
    private Mesh _leafMesh = null!;
    private readonly List<Material> _leafMaterials = new();
    private SurfaceTool? _reedSurface;

    public async Task Build(DaanWorld world, DaanGeometry geometry)
    {
        _map = world;
        _g = geometry;
        _rng.Seed = 92176;
        _leafMesh = SprayMesh();
        var texture = LeafTexture();
        foreach (string color in new[] { "587846", "6c864d", "466c4b", "82945b" })
        {
            var material = new ShaderMaterial { Shader = GD.Load<Shader>("res://shaders/foliage.gdshader") };
            material.SetShaderParameter("leaf_texture", texture);
            material.SetShaderParameter("tint", new Color(color));
            material.SetShaderParameter("wind_amplitude", .09f);
            material.SetShaderParameter("band_lift", .12f);
            _leafMaterials.Add(material);
        }
        Tree(_map.Point(5, 42), 12.4f, true);
        Tree(_map.Point(-39, -19), 9.4f, true);
        Tree(_map.Point(-33, -20), 6.9f, false);
        foreach (var p in new Vector2[] { new(-70, 5), new(-9, -55), new(5, -8), new(-55, 26), new(53, -70), new(-65, 71), new(50, 50) })
            Tree(_map.Point(p.X, p.Y), _rng.RandfRange(8.8f, 12.5f), true);
        for (int i = 0; i < 1100; i++)
        {
            var p = new Vector2(_rng.RandfRange(-117, 69), _rng.RandfRange(-108, 108));
            float lawn = ((p - new Vector2(30, 4)) / new Vector2(23, 28)).Length();
            if (lawn < 1 || !_map.PlantedClear(p.X, p.Y, 1.4f)) continue;
            bool clear = true;
            foreach (var previous in _treePositions)
                if (p.DistanceTo(previous) < 7) { clear = false; break; }
            if (clear) Tree(_map.Point(p.X, p.Y), _rng.RandfRange(5.8f, 13.2f), i % 5 == 0);
        }
        for (int z = -118; z < 119; z += 12)
            foreach (float x in new[] { -125f, -112f }) Tree(_map.Point(x + _rng.RandfRange(-2, 2), z), _rng.RandfRange(10, 16), false);
        for (int x = -105; x < 77; x += 12)
            foreach (float z in new[] { -112f, 111f }) Tree(_map.Point(x, z + _rng.RandfRange(-2, 2)), _rng.RandfRange(11, 16), false);
        for (int z = -87; z < 100; z += 18)
        {
            if (Mathf.Abs(z + 60) < 7 || Mathf.Abs(z - 30) < 7) continue;
            Tree(_map.Point(72, z), 8.5f, false);
            _g.Box(_map.Point(72, z, -.03f), new(2.4f, .12f, 2.4f), "878a69");
        }
        Understory();
        Bamboo();
        PondPlants();
        for (int i = 0; i < 4; i++)
            CozyMeshBatches.Spatial(_g.Root, _leafMesh, _leafMaterials[i], _leafGroups[i], "Subtropical leaf sprays", 32);
        _map.EmitSignal(CozyMap.SignalName.LoadProgress, "Combing the grass and pond reeds…", .78f);
        await _map.ToSignal(_map.GetTree(), SceneTree.SignalName.ProcessFrame);
        Grass();
        GD.Print("Daan Gardens trees: ", _treePositions.Count);
    }

    private static Texture2D LeafTexture()
    {
        var image = Image.CreateEmpty(256, 256, false, Image.Format.Rgba8);
        image.Fill(Colors.Transparent);
        var brush = new RandomNumberGenerator { Seed = 6238 };
        for (int layer = 0; layer < 2; layer++)
            for (int i = 0; i < 74; i++)
            {
                float angle = brush.Randf() * Mathf.Tau;
                float radius = Mathf.Sqrt(brush.Randf()) * 86;
                var at = new Vector2(128, 128) + new Vector2(Mathf.Cos(angle), Mathf.Sin(angle) * .84f) * radius;
                float length = brush.RandfRange(10, 22);
                CozyLeafPainter.Paint(image, at, length, length * brush.RandfRange(.35f, .55f), angle + brush.RandfRange(-.8f, .8f),
                    layer == 0 ? brush.RandfRange(.5f, .78f) : brush.RandfRange(.75f, 1), CozyLeafPainter.Profile.Pointed);
            }
        image.GenerateMipmaps();
        return ImageTexture.CreateFromImage(image);
    }

    private Mesh SprayMesh()
    {
        var surface = new SurfaceTool();
        surface.Begin(Mesh.PrimitiveType.Triangles);
        Vector2[] corners = [new(-1, -1), new(1, -1), new(1, 1), new(-1, 1)];
        for (int i = 0; i < 24; i++)
        {
            var at = new Vector3(_rng.RandfRange(-.48f, .48f), _rng.RandfRange(-.27f, .27f), _rng.RandfRange(-.48f, .48f));
            var normal = new Vector3(_rng.RandfRange(-1, 1), _rng.RandfRange(.2f, 1), _rng.RandfRange(-1, 1)).Normalized();
            var basis = new Basis(new Quaternion(Vector3.Back, normal));
            float size = _rng.RandfRange(.25f, .42f);
            float shade = _rng.RandfRange(.85f, 1.15f);
            surface.SetColor(new Color(shade, shade, shade, .7f));
            foreach (int j in new[] { 0, 1, 2, 0, 2, 3 })
            {
                surface.SetUV(corners[j] * .5f + new Vector2(.5f, .5f));
                surface.SetNormal((at * new Vector3(1, 2, 1) + Vector3.Up * .6f).Normalized());
                surface.AddVertex(at + basis * new Vector3(corners[j].X * size, corners[j].Y * size, 0));
            }
        }
        return surface.Commit();
    }

    private void Leaves(Vector3 at, Vector3 size, int index) =>
        _leafGroups[(index % 4 + 4) % 4].Add(new Transform3D(new Basis(Vector3.Up, _rng.Randf() * Mathf.Tau) * Basis.FromScale(size), at));

    private void Limb(Vector3 a, Vector3 b, float radius)
    {
        var direction = (b - a).Normalized();
        var side = direction.Cross(Vector3.Up);
        if (side.LengthSquared() < .01f) side = Vector3.Right;
        var middle = (a + b) * .5f + side.Normalized() * a.DistanceTo(b) * .045f;
        for (int part = 0; part < 2; part++)
        {
            var from = part == 0 ? a : middle;
            var to = part == 0 ? middle : b;
            float thick = part == 0 ? radius : radius * .75f;
            var overlap = (to - from).Normalized() * radius * .18f;
            if (part == 0) to += overlap;
            else from -= overlap;
            _g.Add(part == 0 ? "branch_base" : "branch_tip", (from + to) * .5f, new(thick * 2, from.DistanceTo(to), thick * 2), "948367",
                new Quaternion(Vector3.Up, (to - from).Normalized()).GetEuler(), false, 4);
            if (radius >= .085f) CozyCollision.Limb(_g.Body, from, to, thick * .72f);
        }
    }

    private void Tree(Vector3 p, float height, bool banyan)
    {
        _treePositions.Add(new(p.X, p.Z));
        float trunk = height * (banyan ? .040f : .022f);
        var lean = new Vector3(_rng.RandfRange(-.7f, .7f), 0, _rng.RandfRange(-.7f, .7f));
        var fork = p + lean + new Vector3(0, height * _rng.RandfRange(.29f, .45f), 0);
        Limb(p, fork, trunk);
        Limb(fork, p + lean * 1.7f + new Vector3(0, height * .79f, 0), trunk * .67f);
        if (banyan)
            for (int i = 0; i < 6; i++)
            {
                float angle = i * Mathf.Tau / 6 + _rng.Randf() * .2f;
                Limb(p + new Vector3(Mathf.Cos(angle) * 1.6f, .08f, Mathf.Sin(angle) * 1.6f),
                    p + new Vector3(Mathf.Cos(angle) * .13f, 1.3f, Mathf.Sin(angle) * .13f), .14f);
            }
        int count = _rng.RandiRange(5, 8);
        for (int branch = 0; branch < count; branch++)
        {
            float angle = branch * 2.399f + _rng.Randf() * .6f;
            float spread = height * (banyan ? _rng.RandfRange(.33f, .49f) : _rng.RandfRange(.23f, .40f));
            var tip = p + lean + new Vector3(Mathf.Cos(angle) * spread, height * _rng.RandfRange(.64f, .96f), Mathf.Sin(angle) * spread);
            var origin = fork + lean * (branch * .09f) + Vector3.Up * (branch % 3 - 1) * height * .055f;
            var elbow = origin.Lerp(tip, .52f) + new Vector3(0, _rng.RandfRange(.2f, 1), 0);
            Limb(origin, elbow, trunk * .55f);
            Limb(elbow, tip, trunk * .31f);
            for (int j = 0; j < 8; j++)
            {
                float a = _rng.Randf() * Mathf.Tau;
                float r = Mathf.Sqrt(_rng.Randf()) * height * .19f;
                var at = tip + new Vector3(Mathf.Cos(a) * r, _rng.RandfRange(-.08f, .09f) * height, Mathf.Sin(a) * r);
                float size = height * _rng.RandfRange(.23f, .33f);
                Leaves(at, new(size * 1.25f, size * .83f, size), branch + j);
            }
            if (banyan && branch % 2 == 0)
                for (int j = 0; j < 4; j++)
                {
                    var hanging = tip + new Vector3(_rng.RandfRange(-.7f, .7f), -.3f, _rng.RandfRange(-.7f, .7f));
                    _g.Beam(hanging, hanging - new Vector3(0, _rng.RandfRange(1.6f, 3), 0), .022f, "93886d");
                }
        }
    }

    private void Understory()
    {
        foreach (var center in new Vector2[] { new(-66, 58), new(-54, 66), new(0, 51), new(-7, 39), new(-79, 30), new(-91, -39), new(47, 48) })
            for (int i = 0; i < 24; i++)
            {
                float x = center.X + _rng.RandfRange(-5, 5);
                float z = center.Y + _rng.RandfRange(-4, 4);
                if (!_map.PlantedClear(x, z, .65f)) continue;
                float size = _rng.RandfRange(1.6f, 3.2f);
                Leaves(_map.Point(x, z, size * .38f), new(size, size * .95f, size), i);
            }
        for (int i = 0; i < 270; i++)
        {
            float x = _rng.RandfRange(-99, 60);
            float z = _rng.RandfRange(-88, 92);
            if (_map.PlantedClear(x, z, .8f) && (x < -58 || z > 34)) Fern(_map.Point(x, z), _rng.RandfRange(.65f, 1.25f));
        }
        for (int i = 0; i < 2600; i++)
        {
            float x = _rng.RandfRange(-110, 70);
            float z = _rng.RandfRange(-103, 102);
            if (!_map.PlantedClear(x, z, .4f)) continue;
            if (((new Vector2(x, z) - new Vector2(30, 4)) / new Vector2(26, 29)).Length() < 1) continue;
            if (Mathf.Sin(x * .17f) + Mathf.Cos(z * .21f) < -.3f) continue;
            var p = _map.Point(x, z);
            float size = _rng.RandfRange(.6f, 1.7f);
            Leaves(p + new Vector3(0, size * .27f, 0), new(size, size * .7f, size), i);
            if (i % 7 == 0)
                for (int j = 0; j < 4; j++)
                {
                    var q = p + new Vector3(_rng.RandfRange(-.4f, .4f), size * .45f, _rng.RandfRange(-.4f, .4f));
                    _g.Add("sphere", q, new(.12f, .10f, .12f), new[] { "dbc798", "c6aa91", "d9d6b7" }[j % 3]);
                }
        }
    }

    private void Bamboo()
    {
        foreach (var center in new Vector2[] { new(-91, 50), new(-88, 67), new(-66, 39) })
            for (int i = 0; i < 37; i++)
            {
                var p = _map.Point(center.X + _rng.RandfRange(-4, 4), center.Y + _rng.RandfRange(-4, 4));
                if (_map.PathDistance(p.X, p.Z) < .7f) continue;
                float height = _rng.RandfRange(5, 8);
                _g.Beam(p, p + new Vector3(.35f, height, .2f), .065f, "85966c");
                for (int j = 1; j < 11; j++)
                {
                    var at = p + new Vector3(.35f, height, .2f) * j / 11;
                    _g.Add("cylinder", at, new(.15f, .045f, .15f), "b8b78b");
                    if (j > 5) Leaves(at + new Vector3(Mathf.Sin(j) * .8f, 0, Mathf.Cos(j) * .8f), new(1.8f, .45f, 1.4f), j);
                }
            }
    }

    private void PondPlants()
    {
        _reedSurface = new SurfaceTool();
        _reedSurface.Begin(Mesh.PrimitiveType.Triangles);
        for (int i = 0; i < 50; i++)
        {
            var p = DaanWorld.Island + new Vector2(_rng.RandfRange(-8, 8), _rng.RandfRange(-6, 6));
            if (_map.IslandRadius(p.X, p.Y) > 1.04f) continue;
            float size = _rng.RandfRange(.5f, 1.4f);
            Leaves(_map.Point(p.X, p.Y, size * .3f), new(size, size * .8f, size), i);
            if (i % 4 == 0) _g.Add("sphere", _map.Point(p.X, p.Y, -.06f), new(.6f, .4f, .7f), "a4a88b");
        }
        for (int i = 0; i < 550; i++)
        {
            float angle = _rng.Randf() * Mathf.Tau;
            float r = _rng.RandfRange(.96f, 1.05f);
            float wave = 1 + .065f * Mathf.Sin(angle * 3) + .035f * Mathf.Cos(angle * 5);
            var p = _map.Point(DaanWorld.Pond.X + Mathf.Cos(angle) * 30 * wave * r, DaanWorld.Pond.Y + Mathf.Sin(angle) * 23 * wave * r);
            if (p.X > -5 && p.X < 9 && p.Z > -27 && p.Z < -19) continue;
            if (angle > 0 && angle < 1.1f) continue;
            for (int j = 0; j < 3; j++)
            {
                var q = p + new Vector3(_rng.RandfRange(-.3f, .3f), 0, _rng.RandfRange(-.3f, .3f));
                float height = _rng.RandfRange(.45f, 1.35f);
                _g.Beam(q, q + new Vector3(.07f, height, .06f), .018f, "74834f");
                if (j == 0) _g.Add("cylinder", q + new Vector3(.07f, height, .06f), new(.055f, .18f, .055f), "887857");
                ReedLeaves(q, height, angle + j * 2.399f);
            }
            if (i % 3 == 0) Leaves(p + new Vector3(0, .25f, 0), new(.8f, .6f, .8f), i);
        }
        for (int i = 0; i < 34; i++)
        {
            float angle = i * 2.399f;
            var p = DaanWorld.Pond + new Vector2(Mathf.Cos(angle) * 33.5f, Mathf.Sin(angle) * 26);
            if (_map.PlantedClear(p.X, p.Y, 1.1f)) Fern(_map.Point(p.X, p.Y), .85f + .3f * Mathf.Sin(i * 1.7f));
        }
        _reedSurface.GenerateNormals();
        _g.Mesh(_reedSurface.Commit(), "74894b");
        _reedSurface.Dispose();
        _reedSurface = null;
        for (int i = 0; i < 110; i++)
        {
            var p = DaanWorld.Pond + new Vector2(_rng.RandfRange(-23, 18), _rng.RandfRange(-15, 13));
            if (_map.PondRadius(p.X, p.Y) > .87f || _map.IslandRadius(p.X, p.Y) < 1.25f) continue;
            if (Mathf.Sin(p.X * .35f) + Mathf.Cos(p.Y * .3f) < .2f) continue;
            _g.Add("cylinder", new(p.X, .535f, p.Y), new(_rng.RandfRange(.25f, .65f), .025f, _rng.RandfRange(.25f, .6f)), "82945a");
            if (i % 9 == 0) _g.Add("sphere", new(p.X, .60f, p.Y), new(.14f, .1f, .14f), "e6ccb8");
        }
    }

    private void Grass()
    {
        var surface = new SurfaceTool();
        surface.Begin(Mesh.PrimitiveType.Triangles);
        for (int blade = 0; blade < 4; blade++)
        {
            float angle = blade * 2.399f;
            var side = new Vector3(Mathf.Cos(angle), 0, Mathf.Sin(angle)) * .05f;
            var root = new Vector3(Mathf.Sin(angle), 0, Mathf.Cos(angle)) * .1f;
            var tip = root + new Vector3(Mathf.Cos(angle) * .22f, 1, Mathf.Sin(angle) * .22f);
            for (int row = 0; row < 3; row++)
            {
                float t = row / 3f;
                float next = (row + 1) / 3f;
                var a = root.Lerp(tip, t);
                var b = root.Lerp(tip, next);
                foreach (var item in new[] { (a - side * (1 - t), t), (b - side * (1 - next), next), (b + side * (1 - next), next),
                    (a - side * (1 - t), t), (b + side * (1 - next), next), (a + side * (1 - t), t) })
                {
                    surface.SetNormal(Vector3.Up);
                    surface.SetColor(Colors.White);
                    surface.SetUV(new Vector2(0, item.Item2));
                    surface.AddVertex(item.Item1);
                }
            }
        }
        List<Transform3D> instances = new();
        for (int i = 0; i < 270000; i++)
        {
            float x = _rng.RandfRange(-130, 73);
            float z = _rng.RandfRange(-119, 119);
            if (_map.DeckFootprint(x, z, .35f) || _map.PathDistance(x, z) < .14f || _map.PondRadius(x, z) < 1.095f) continue;
            bool clear = true;
            foreach (var plaza in new Vector3[] { new(5, 42, 11.2f), new(-52, 56, 9.2f), new(62, -60, 9.2f) })
                if (new Vector2(x - plaza.X, z - plaza.Y).Length() < plaza.Z) { clear = false; break; }
            if (!clear) continue;
            bool lawn = ((new Vector2(x, z) - new Vector2(30, 4)) / new Vector2(26, 29)).Length() < 1;
            float size = lawn ? _rng.RandfRange(.08f, .19f) : _rng.RandfRange(.18f, .43f);
            instances.Add(new Transform3D(new Basis(Vector3.Up, _rng.Randf() * Mathf.Tau) * Basis.FromScale(new Vector3(.8f, size, .8f)), _map.Point(x, z)));
        }
        var material = new ShaderMaterial { Shader = GD.Load<Shader>("res://shaders/grass.gdshader") };
        material.SetShaderParameter("grass_base", new Vector3(.28f, .39f, .20f));
        material.SetShaderParameter("grass_mid", new Vector3(.44f, .51f, .27f));
        material.SetShaderParameter("grass_tip", new Vector3(.62f, .62f, .36f));
        int batches = CozyMeshBatches.Spatial(_g.Root, surface.Commit(), material, instances, "Park grass", 24, 105, 12, GeometryInstance3D.ShadowCastingSetting.Off);
        GD.Print("Daan Gardens grass: ", instances.Count, " in ", batches, " batches");
    }

    private void ReedLeaves(Vector3 p, float height, float phase)
    {
        for (int leaf = 0; leaf < 3; leaf++)
        {
            float angle = phase + leaf * 2.399f;
            var direction = new Vector3(Mathf.Cos(angle), 0, Mathf.Sin(angle));
            var side = direction.Cross(Vector3.Up);
            var root = p + Vector3.Up * height * (.15f + leaf * .13f);
            for (int segment = 0; segment < 4; segment++)
                foreach (int k in new[] { 0, 2, 1, 1, 2, 3 })
                {
                    // Integer division is intentional: each pair shares its longitudinal station.
                    float t = (segment + k / 2) / 4f;
                    var point = root + direction * t * height * .5f + Vector3.Up * Mathf.Sin(t * Mathf.Pi * .85f) * height * .32f;
                    point += side * (k % 2 == 0 ? -1 : 1) * Mathf.Sin(t * Mathf.Pi) * height * .047f;
                    _reedSurface!.AddVertex(point);
                }
        }
    }

    private void Fern(Vector3 p, float size)
    {
        var surface = new SurfaceTool();
        surface.Begin(Mesh.PrimitiveType.Triangles);
        for (int frond = 0; frond < 8; frond++)
        {
            float angle = frond * 2.399f;
            var forward = new Vector3(Mathf.Cos(angle), 0, Mathf.Sin(angle));
            var side = forward.Cross(Vector3.Up);
            for (int leaf = 1; leaf < 8; leaf++)
            {
                float t = leaf / 8f;
                var center = p + forward * t * size + Vector3.Up * Mathf.Sin(t * Mathf.Pi * .78f) * size * .65f;
                float width = Mathf.Sin(t * Mathf.Pi) * size * .26f;
                foreach (int sign in new[] { -1, 1 })
                {
                    var tip = center + side * width * sign + forward * .12f * size;
                    foreach (var point in new[] { center - forward * .05f, tip, center + forward * .06f }) surface.AddVertex(point);
                }
            }
        }
        surface.GenerateNormals();
        _g.Mesh(surface.Commit(), "7d9858");
    }
}
