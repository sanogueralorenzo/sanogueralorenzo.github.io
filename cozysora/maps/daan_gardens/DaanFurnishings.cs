using Godot;

namespace CozySora;

public sealed class DaanFurnishings
{
    private DaanWorld _map = null!;
    private DaanGeometry _g = null!;
    private readonly RandomNumberGenerator _rng = new();

    public void Build(DaanWorld world, DaanGeometry geometry)
    {
        _map = world;
        _g = geometry;
        _rng.Seed = 46199;
        Pavilion(_map.Point(-52, 56));
        var p = _map.Point(62, -65);
        _g.Box(p + new Vector3(0, .72f, 0), new(6.1f, 1.44f, .6f), "898e78", true);
        _g.Box(p + new Vector3(0, 1.46f, 0), new(6.3f, .12f, .75f), "c2bda0");
        _g.Label("DAAN GARDENS", p + new Vector3(0, .96f, .315f), 4.9f, "eee4c5");
        _g.Label("POND  ·  BANYAN COURT  ·  TEA PAVILION", p + new Vector3(0, .47f, .32f), 5.2f, "dedbc0");
        foreach (float x in new[] { -3.7f, 3.7f }) _g.Add("cylinder", p + new Vector3(x, .3f, 0), new(.85f, .6f, .85f), "9c8d76", default, true);
        foreach (var info in new Vector3[] { new(-1, -47, .6f), new(-68, 2, 1.5f), new(4, 31, 2.8f), new(-44, 67, -.6f), new(47, 56, -.9f), new(57, -34, -1.5f) })
            Bench(_map.Point(info.X, info.Y), info.Z);
        for (int i = 0; i < 6; i++)
        {
            float a = i * Mathf.Tau / 6;
            Bench(_map.Point(5 + Mathf.Sin(a) * 4.5f, 42 + Mathf.Cos(a) * 4.5f), a);
        }
        foreach (var path in _map.Paths.Take(2))
            for (int i = 8; i < path.Points.Count - 3; i += 26)
            {
                var a = path.Points[i];
                var b = path.Points[i + 1];
                var side = (b - a).Normalized().Orthogonal() * (path.Width * .5f + .8f);
                Lamp(_map.Point(a.X + side.X, a.Y + side.Y));
            }
        foreach (var at in new Vector2[] { new(65, -58), new(-2, -46), new(7, 34), new(-44, 57) }) Bin(_map.Point(at.X, at.Y));
        Deck();
        for (int i = 0; i < 175; i++)
        {
            float a = i * Mathf.Tau / 175;
            float wave = 1 + .065f * Mathf.Sin(a * 3) + .035f * Mathf.Cos(a * 5);
            var at = _map.Point(DaanWorld.Pond.X + Mathf.Cos(a) * 30 * wave * 1.015f, DaanWorld.Pond.Y + Mathf.Sin(a) * 23 * wave * 1.015f);
            _g.Add("sphere", at + new Vector3(0, -.03f, 0), new(_rng.RandfRange(.8f, 1.4f), _rng.RandfRange(.35f, .6f), _rng.RandfRange(.6f, 1.1f)),
                new[] { "969a85", "898f7e", "b1ae93" }[i % 3], new(0, a, 0));
        }
        Sign(_map.Point(-1, -41), "THE LIVING POND", "A quiet home for egrets and water lilies", .35f);
        Sign(_map.Point(-62, 49), "THE BAMBOO WALK", "Shade, birdsong, and the long way home", -1);
        for (int z = -98; z < 100; z += 4)
        {
            if (Mathf.Abs(z + 60) < 6 || Mathf.Abs(z - 30) < 6) continue;
            var at = _map.Point(74, z);
            _g.Add("cylinder", at + new Vector3(0, .5f, 0), new(.08f, 1, .08f), "6b7865");
            _g.Beam(at + new Vector3(0, .88f, 0), at + new Vector3(0, .88f, 4), .035f, "6b7865");
        }
    }

    private void Bench(Vector3 p, float yaw)
    {
        var turn = new Basis(Vector3.Up, yaw);
        foreach (float x in new[] { -.95f, .95f })
            foreach (float z in new[] { -.25f, .25f }) _g.Box(p + turn * new Vector3(x, .24f, z), new(.09f, .48f, .09f), "596b60", false, yaw);
        foreach (float z in new[] { -.25f, -.08f, .09f, .26f }) _g.Box(p + turn * new Vector3(0, .49f, z), new(2.35f, .075f, .13f), "a18b61", false, yaw, 3);
        foreach (float y in new[] { .73f, .9f }) _g.Box(p + turn * new Vector3(0, y, -.31f), new(2.35f, .13f, .07f), "a18b61", false, yaw, 3);
        foreach (int x in new[] { -1, 1 }) _g.Box(p + turn * new Vector3(x, .68f, -.31f), new(.06f, .64f, .07f), "596b60", false, yaw);
        CozyCollision.Box(_g.Body, p + new Vector3(0, .28f, 0), new(2.35f, .56f, .65f), new(0, yaw, 0));
    }

    private void Lamp(Vector3 p)
    {
        _g.Add("cylinder", p + new Vector3(0, 1.95f, 0), new(.11f, 3.9f, .11f), "697c70", default, true);
        _g.Add("cylinder", p + new Vector3(0, .14f, 0), new(.28f, .28f, .28f), "697c70");
        _g.Add("cylinder", p + new Vector3(0, 3.75f, 0), new(.48f, .14f, .48f), "d4cfac");
        _g.Add("cylinder", p + new Vector3(0, 3.89f, 0), new(.65f, .08f, .65f), "697c70");
    }

    private void Bin(Vector3 p)
    {
        _g.Box(p + new Vector3(0, .44f, 0), new(.52f, .88f, .52f), "718271", true);
        _g.Box(p + new Vector3(0, .82f, .27f), new(.3f, .18f, .025f), "384f48");
        _g.Box(p + new Vector3(0, .91f, 0), new(.6f, .07f, .6f), "a8a689");
    }

    private void Sign(Vector3 p, string title, string caption, float yaw)
    {
        var turn = new Basis(Vector3.Up, yaw);
        foreach (float x in new[] { -.64f, .64f }) _g.Box(p + turn * new Vector3(x, .65f, 0), new(.08f, 1.3f, .08f), "6b7966", false, yaw);
        _g.Box(p + new Vector3(0, 1.25f, 0), new(1.9f, .8f, .12f), "6a7966", true, yaw);
        _g.Label(title, p + turn * new Vector3(0, 1.43f, .07f), 1.65f, "e5ddba", yaw);
        _g.Label(caption, p + turn * new Vector3(0, 1.13f, .07f), 1.65f, "c6cbb0", yaw);
    }

    private void Pavilion(Vector3 p)
    {
        _g.Box(p + new Vector3(0, .02f, 0), new(8, .04f, 7), "b5ae94", false, 0, 1);
        foreach (float x in new[] { -3.3f, 0, 3.3f })
            foreach (float z in new[] { -2.65f, 2.65f })
            {
                _g.Box(p + new Vector3(x, 1.65f, z), new(.24f, 3.3f, .24f), "8b7556", true, 0, 3);
                _g.Box(p + new Vector3(x, .14f, z), new(.44f, .28f, .44f), "a3a28a");
            }
        foreach (float z in new[] { -2.65f, 2.65f }) _g.Box(p + new Vector3(0, 3.1f, z), new(7, .23f, .25f), "8b7556", false, 0, 3);
        foreach (float x in new[] { -3.3f, 3.3f }) _g.Box(p + new Vector3(x, 3.1f, 0), new(.25f, .23f, 5.6f), "8b7556", false, 0, 3);
        var surface = new SurfaceTool();
        surface.Begin(Mesh.PrimitiveType.Triangles);
        Vector3[] points = [new(-4.5f, 3.35f, -3.8f), new(4.5f, 3.35f, -3.8f), new(4.5f, 3.35f, 3.8f),
            new(-4.5f, 3.35f, 3.8f), new(-1.6f, 4.9f, 0), new(1.6f, 4.9f, 0)];
        foreach (int i in new[] { 0, 1, 5, 0, 5, 4, 1, 2, 5, 2, 3, 4, 2, 4, 5, 3, 0, 4 }) surface.AddVertex(p + points[i]);
        surface.GenerateNormals();
        _g.Mesh(surface.Commit(), "657b6a", true);
        var underside = new SurfaceTool();
        underside.Begin(Mesh.PrimitiveType.Triangles);
        foreach (int i in new[] { 5, 1, 0, 4, 5, 0, 5, 2, 1, 4, 3, 2, 5, 4, 2, 4, 0, 3 }) underside.AddVertex(p + points[i] - new Vector3(0, .08f, 0));
        underside.GenerateNormals();
        _g.Mesh(underside.Commit(), "a8956e", true, 3);
        foreach (float x in new[] { -2.7f, 0, 2.7f }) _g.Box(p + new Vector3(x, 3.26f, 0), new(.12f, .16f, 7.2f), "8c7858", false, 0, 3);
        for (int i = 0; i < 37; i++)
        {
            float x = -4.5f + i * .25f;
            float ridgeX = Mathf.Clamp(x, -1.6f, 1.6f);
            foreach (int side in new[] { -1, 1 }) _g.Beam(p + new Vector3(x, 3.39f, side * 3.8f), p + new Vector3(ridgeX, 4.94f, 0), .045f, "7b8d75");
        }
        foreach (float z in new[] { -3.8f, 3.8f }) _g.Box(p + new Vector3(0, 3.34f, z), new(9.2f, .16f, .16f), "556d60");
        _g.Beam(p + new Vector3(-1.8f, 4.98f, 0), p + new Vector3(1.8f, 4.98f, 0), .11f, "89957b");
        foreach (int x in new[] { -3, 3 }) Bench(p + new Vector3(x, 0, 0), x < 0 ? Mathf.Pi * .5f : -Mathf.Pi * .5f);
        foreach (float z in new[] { -1.3f, 1.3f })
        {
            _g.Add("cylinder", p + new Vector3(0, .37f, z), new(.28f, .74f, .28f), "879582");
            _g.Add("cylinder", p + new Vector3(0, .76f, z), new(1.1f, .08f, 1.1f), "b3a47d", default, true);
        }
        _g.Box(p + new Vector3(0, 2.9f, 2.8f), new(2.7f, .5f, .08f), "697d6b");
        _g.Label("AFTERNOON PAVILION", p + new Vector3(0, 2.91f, 2.85f), 2.3f, "e2d8b4");
    }

    private void Deck()
    {
        var p = new Vector3(-1, 1.32f, -23);
        _g.Box(p - new Vector3(0, .12f, 0), new(7, .24f, 6), "7a735b", true);
        for (int i = 0; i < 28; i++) _g.Box(p + new Vector3(-3.375f + i * .25f, .012f, 0), new(.225f, .035f, 6), "a79773", false, 0, 3);
        _g.Ribbon([new(2.5f, 1.34f, -23), _map.Point(8, -23, .05f)], 2.6f, "a79773", 3, true, false);
        foreach (float x in new[] { -3.45f, 3.45f })
            foreach (int z in new[] { -3, 3 }) _g.Box(p + new Vector3(x, .48f, z), new(.12f, .96f, .12f), "73816b", true);
        foreach (int z in new[] { -3, 3 })
        {
            _g.Beam(p + new Vector3(-3.45f, .92f, z), p + new Vector3(3.45f, .92f, z), .055f, "73816b");
            _g.Beam(p + new Vector3(-3.45f, .46f, z), p + new Vector3(3.45f, .46f, z), .028f, "73816b");
        }
        _g.Beam(p + new Vector3(-3.45f, .92f, -3), p + new Vector3(-3.45f, .92f, 3), .055f, "73816b");
        CozyCollision.Box(_g.Body, p + new Vector3(-3.45f, .5f, 0), new(.14f, 1, 6));
        foreach (int z in new[] { -3, 3 }) CozyCollision.Box(_g.Body, p + new Vector3(0, .5f, z), new(7, 1, .12f));
    }
}
