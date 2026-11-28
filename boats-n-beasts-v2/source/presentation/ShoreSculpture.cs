using Godot;

namespace BoatsNBeasts;

public static partial class ActorArt3D
{
    public static Node3D ShoreSkiff()
    {
        const string key = "quay-skiff";
        if (!Cache.TryGetValue(key, out var mesh))
        {
            var b = new ActorGeometry();
            b.Loft([HullRing(-.06f, .62f), HullRing(.03f, .85f), HullRing(.15f, .97f), HullRing(.19f, 1)],
                [DarkWood, new Color("37766e"), Brass]);
            b.Polygon(HullRing(.191f, 1), DarkWood, Vector3.Up);
            for (int j = -2; j <= 2; j++)
            {
                float z = j * .17f, width = Width(z) * 1.74f;
                b.RoundBox(new(0, .217f, z), new(width, .034f, .073f), .008f, Wood.Lightened(.1f));
            }
            b.ClosedTube(HullRing(.216f, 1), .017f, Brass, 6);
            foreach (int side in new[] { -1, 1 })
            {
                b.Tube([new(side * .1f, .256f, -.36f), new(side * .23f, .256f, .23f)], .012f, Brass, 6);
                b.RoundBox(new(side * .23f, .256f, .27f), new(.068f, .014f, .14f), .006f, Wood);
            }
            b.Scale(new(2.55f, 1.83f, 2.8f));
            Cache[key] = mesh = b.Mesh(Material);
        }
        return Instance(mesh, key);
    }

    public static Node3D LandingParty(int role)
    {
        string key = $"landing-party-{role}";
        if (!Cache.TryGetValue(key, out var mesh))
        {
            var body = new ActorGeometry();
            Crewmate(body, Vector3.Zero, role);
            if (role == 0)
            {
                body.Tube([new(.096f, .14f, -.09f), new(.12f, .19f, -.20f), new(.14f, .23f, -.23f)],
                    [.012f, .015f, .002f], new("dce6e2"), 5);
                body.Tube([new(.077f, .14f, -.11f), new(.117f, .14f, -.08f)], .008f, Brass, 5);
            }
            body.Scale(Vector3.One * 2.85f);
            Cache[key] = mesh = body.Mesh(Material);
        }
        return Instance(mesh, key);
    }
}

internal static class ShoreSculpture
{
    public const float Floor = .48f;
    static readonly Color Gold = new("e7b46b"), Teal = new("367e78"), Ink = new("37364a"),
        Rust = new("a96044"), Stone = new("615a6a"), Planks = new("ad7049");
    public static MeshInstance3D Bake(ActorGeometry b) => new() { Mesh = b.Mesh(DioramaSurface.Material) };
    static Vector3[] Ring(float radius, float y, int count = 12) =>
        Enumerable.Range(0, count).Select(i => new Vector3(MathF.Cos(i * Mathf.Tau / count) * radius, y, MathF.Sin(i * Mathf.Tau / count) * radius)).ToArray();

    public static MeshInstance3D Keeper(bool warden)
    {
        var b = new ActorGeometry();
        var rim = Ring(.74f, .62f);
        b.Loft([rim, Ring(.78f, .71f), Ring(.68f, .81f), Ring(.55f, 1.43f), Ring(.42f, 1.54f)],
            [Ink, Gold, Teal, Gold]);
        b.Polygon(Ring(.42f, 1.54f), Stone, Vector3.Up);
        b.Ring(new(0, .85f, 0), .68f, .032f, Rust);
        b.Ring(new(0, 1.32f, 0), .57f, .025f, Gold);
        b.Sphere(new(0, 1.67f, 0), new(.43f, .34f, .38f), Stone, 8, 5);
        b.Sphere(new(0, 1.62f, -.33f), new(.32f, .13f, .11f), Ink);
        b.Tube([new(-.23f, 1.66f, -.408f), new(-.06f, 1.61f, -.443f)], .03f, Gold, 6);
        b.Tube([new(.23f, 1.66f, -.408f), new(.06f, 1.61f, -.443f)], .03f, Gold, 6);
        var crown = Enumerable.Range(0, 14).Select(i =>
        {
            float a = i * Mathf.Tau / 13;
            return new Vector3(.20f * MathF.Cos(a), 1.96f + .20f * MathF.Sin(a), 0);
        }).ToArray();
        b.Tube(crown, .063f, Gold, 7);
        foreach (int sign in new[] { -1, 1 })
        {
            b.Sphere(new(sign * .45f, .35f, 0), new(.23f, .30f, .23f), Stone, 6, 4);
            b.Sphere(new(sign * .51f, .12f, -.09f), new(.32f, .13f, .34f), Ink, 7, 4);
            b.Sphere(new(sign * .63f, 1.47f, 0), new(.34f, .36f, .30f), Rust, 6, 4);
            b.Sphere(new(sign * .66f, 1.51f, -.13f), new(.24f, .24f, .22f), Gold, 7, 5);
            b.Tube([new(sign * .69f, 1.4f, 0), new(sign * .91f, 1.06f, -.03f), new(sign * 1.05f, .85f, -.23f)],
                [.17f, .16f, .145f], Ink, 7);
            b.Sphere(new(sign * .88f, 1.18f, 0), new(.23f, .23f, .23f), Stone, 6, 4);
        }
        b.Sphere(new(-1.08f, .73f, -.19f), new(.28f, .29f, .32f), Stone, 7, 4);
        b.Tube([new(1.00f, .84f, -.17f), new(1.42f, .75f, -.56f)], .075f, Rust);
        b.Sphere(new(1.48f, .75f, -.60f), new(.27f, .25f, .29f), Gold, 8, 5);
        b.Sphere(new(1.52f, .76f, -.62f), new(.24f, .26f, .27f), Teal, 8, 5);
        for (int i = 0; i < 12; i++)
        {
            var a = Mathf.Tau * i / 12;
            b.Sphere(new(.725f * MathF.Cos(a), .75f, .725f * MathF.Sin(a)), Vector3.One * .035f, Gold, 6, 3);
        }
        b.Tube([new(-.16f, 1.32f, -.56f), new(.035f, 1.21f, -.61f), new(-.06f, 1.13f, -.64f), new(.12f, .87f, -.67f)], .026f, Gold, 5);
        var result = Bake(b);
        result.Scale = Vector3.One * (warden ? 1.04f : .49f);
        return result;
    }

    public static MeshInstance3D Quay(int seed, bool belfry = false)
    {
        var b = new ActorGeometry();
        var rng = new Random(seed);
        static Vector3 Ellipse(float a, float x, float z, float y) => new(x * MathF.Cos(a), y, z * MathF.Sin(a));
        const int sides = 44;
        var top = new Vector3[sides];
        for (int i = 0; i < sides; i++) top[i] = Ellipse(i * Mathf.Tau / sides, 5.45f, 4.07f, Floor);
        b.Polygon(top, new("bd8463"), Vector3.Up);
        Color[] wall = [new("c77257"), new("ac6255"), new("db9062"), new("b97861")];
        var middle = Enumerable.Range(0, sides).Select(i => Ellipse(i * Mathf.Tau / sides, 5.65f + rng.NextSingle() * .30f, 4.27f + rng.NextSingle() * .29f, .14f + rng.NextSingle() * .10f)).ToArray();
        for (int i = 0; i < sides; i++)
        {
            float a = Mathf.Tau * i / sides, next = Mathf.Tau * (i + 1) / sides;
            var t = top[i]; var n = top[(i + 1) % sides];
            var m = middle[i];
            var o = middle[(i + 1) % sides];
            var low = Ellipse(a, 6.03f, 4.72f, -.16f); var lowNext = Ellipse(next, 6.03f, 4.72f, -.16f);
            var normal = (t with { Y = 0 }).Normalized();
            b.Polygon([t, n, o, m], wall[i % 4], normal + Vector3.Up);
            b.Polygon([m, o, lowNext, low], wall[(i + 1) % 4].Darkened(.10f), normal);
            if (i % 3 == 0)
            {
                var p = Ellipse(a, 5.8f + rng.NextSingle() * .3f, 4.6f, .06f);
                b.Sphere(p, new(.39f, .28f + rng.NextSingle() * .24f, .31f), wall[i % 4], 6, 4);
            }
        }
        Color[] tiles = [new("ddaa82"), new("dfad86"), new("e5b78b"), new("dcad87"), new("e1ae88")];
        const float cellX = .83f, cellZ = .64f;
        Vector3 Corner(int col, int row) => new(col * cellX + (row % 2) * .21f + .075f * MathF.Sin(row * 1.4f + col * .81f), Floor + .012f, row * cellZ + .06f * MathF.Sin(col * 2.1f + row * .75f));
        for (int row = -7; row < 7; row++) for (int col = -8; col < 8; col++)
        {
            Vector3[] tile = [Corner(col, row), Corner(col + 1, row), Corner(col + 1, row + 1), Corner(col, row + 1)];
            if (tile.Any(t => new Vector2(t.X / 5.42f, t.Z / 4.05f).LengthSquared() > 1)) continue;
            var center = (tile[0] + tile[2]) * .5f; var tint = tiles[rng.Next(tiles.Length)];
            for (int k = 0; k < 4; k++) tile[k] = tile[k].Lerp(center, .018f);
            b.Polygon(tile, tint, Vector3.Up);
            if (rng.NextDouble() < .55)
            {
                var p = center + new Vector3(rng.NextSingle() * .22f - .11f, .002f, rng.NextSingle() * .14f);
                for (int k = 0; k < 3; k++)
                {
                    var tip = p + new Vector3(.08f + k * .028f, 0, -.045f - k * .013f);
                    b.Polygon([p, tip, p + new Vector3(.012f, 0, .006f)], tint.Darkened(.09f), Vector3.Up);
                    p += new Vector3(.045f, 0, .024f);
                }
            }
        }
        for (int i = 0; !belfry && i < 14; i++)
        {
            float z = 2.85f + i * .145f;
            b.RoundBox(new(-2.4f, Floor - .035f, z), new(1.30f, .16f, .138f), .02f, Planks.Lightened(i % 3 * .055f));
        }
        for (int i = 0; !belfry && i < 3; i++) foreach (int sign in new[] { -1, 1 })
        {
            var p = new Vector3(-2.4f + sign * .67f, 0, 3.00f + i * .76f);
            b.Tube([p, p + Vector3.Up * .76f], .077f, Planks.Darkened(.27f), 7);
            b.Ring(p + Vector3.Up * .66f, .078f, .021f, Gold);
        }
        if (belfry) Arch(b);
        for (int i = 0; i < 26; i++)
        {
            float a = Mathf.Pi + .10f + i * (Mathf.Pi - .2f) / 25;
            if (MathF.Abs(MathF.Cos(a)) < .29f || !belfry && MathF.Abs(MathF.Cos(a)) < .57f) continue;
            var p = Ellipse(a, 4.92f, 3.8f, Floor);
            float height = .3f + rng.NextSingle() * .57f;
            b.Sphere(p + Vector3.Up * height * .44f, new(.44f, height, .42f), wall[i % 4], 6, 4);
        }
        foreach (var p in new[] { new Vector3(-4.85f, Floor, -1.7f), new Vector3(4.6f, Floor, -2.0f), new Vector3(5.05f, Floor, .7f), new Vector3(-4.6f, Floor, 1.45f) })
            Palm(b, p, rng);
        foreach (int sign in new[] { -1, 1 })
        {
            var p = new Vector3(sign * 3.55f, Floor, -2.2f);
            b.Tube([p, p + new Vector3(.06f, 1.55f, 0)], .047f, Planks.Darkened(.25f), 6);
            b.Polygon([p + new Vector3(.04f, 1.48f, 0), p + new Vector3(.64f, 1.33f, .14f), p + new Vector3(.44f, 1.19f, .12f), p + new Vector3(.59f, 1.08f, .18f), p + new Vector3(.06f, 1.18f, 0)], new("ad4c48"), Vector3.Back);
        }
        return Bake(b);
    }

    public static MeshInstance3D Causeway(System.Numerics.Vector2 start, System.Numerics.Vector2 end)
    {
        Vector3 a = new(start.X, Floor + .005f, start.Y), z = new(end.X, Floor + .005f, end.Y);
        var forward = (z - a).Normalized(); var side = forward.Cross(Vector3.Up) * .70f;
        var b = new ActorGeometry();
        int count = (int)MathF.Ceiling(a.DistanceTo(z) / .23f);
        for (int i = 0; i < count; i++)
        {
            var left = a.Lerp(z, i / (float)count) + forward * .009f;
            var right = a.Lerp(z, (i + 1f) / count) - forward * .009f;
            var board = new[] { left - side, left + side, right + side, right - side };
            var color = Planks.Lightened((i % 4) * .05f);
            b.Polygon(board, color, Vector3.Up);
            foreach (int sign in new[] { -1, 1 })
                b.Polygon([left + side * sign, right + side * sign, right + side * sign - Vector3.Up * .09f, left + side * sign - Vector3.Up * .09f], Planks.Darkened(.18f), side * sign);
        }
        foreach (int sign in new[] { -1, 1 })
        {
            for (int i = 0; i <= 4; i++)
            {
                var p = a.Lerp(z, i / 4f) + side * sign;
                b.Tube([p - Vector3.Up * .7f, p + Vector3.Up * .37f], .055f, Planks.Darkened(.21f), 7);
                b.Ring(p + Vector3.Up * .28f, .057f, .015f, Gold);
                if (i < 4)
                {
                    var next = a.Lerp(z, (i + 1) / 4f) + side * sign;
                    b.Tube([p + Vector3.Up * .28f, p.Lerp(next, .5f) + Vector3.Up * .18f, next + Vector3.Up * .28f], .021f, Gold, 5);
                }
            }
        }
        return Bake(b);
    }
    public static MeshInstance3D Station(int kind)
    {
        var b = new ActorGeometry(); const int sides = 25;
        Color stone = new(kind == 0 ? "c5a385" : "c8866b"), edge = new(kind == 0 ? "988679" : "b07060");
        Vector3[] Row(float radius, float y) => Enumerable.Range(0, sides).Select(i =>
        {
            float angle = Mathf.Tau * i / sides;
            return new Vector3(MathF.Cos(angle) * 2.79f * radius, y, MathF.Sin(angle) * 2.53f * radius);
        }).ToArray();
        b.Loft([Row(1.18f, -.17f), Row(1.13f, .12f), Row(1, Floor)], [edge.Darkened(.22f), edge]);
        b.Polygon(Row(1, Floor), stone, Vector3.Up);
        for (int i = 0; i < 4; i++) for (int j = 0; j < 5; j++)
        {
            float x = (i - 1.5f) * .70f, z = (j - 2) * .67f;
            b.RoundBox(new(x, Floor + .003f, z), new(.686f, .023f, .65f), .013f, stone.Lightened((i + j) % 3 * .032f));
        }
        if (kind == 0)
        {
            foreach (int sign in new[] { -1, 1 })
            {
                var p = new Vector3(sign * .82f, Floor, -1.65f);
                b.Tube([p, p + Vector3.Up * 1.25f], .061f, Planks, 7);
            }
            for (int i = 0; i < 9; i++)
            {
                float x = (i - 4) * .20f;
                b.Tube([new(x, 1.63f, -1.65f), new(-x * .35f, .85f, -1.62f)], .012f, Gold, 5);
                b.Tube([new(x, 1.63f, -1.65f), new(x * .55f, .87f, -1.62f)], .012f, Gold, 5);
                if (i % 2 == 0) b.Sphere(new(x * .64f, 1.25f, -1.62f), new(.048f, .13f, .03f), new("8eb0ad"), 7, 4);
            }
            b.Tube([new(-.85f, 1.66f, -1.65f), new(.85f, 1.66f, -1.65f)], .035f, Planks);
            for (int j = 0; j < 2; j++) for (int i = 0; i < 3; i++) b.Ring(new(-1.13f, Floor + .05f + i * .045f, 1.14f + j * .3f), .18f, .029f, Gold);
        }
        else
        {
            foreach (int sign in new[] { -1, 1 }) b.Tube([new(sign * .86f, Floor, -1.53f), new(sign * .86f, 1.85f, -1.53f)], .067f, Planks, 7);
            for (int i = 0; i < 6; i++)
            {
                float x = -.95f + i * .32f;
                var color = i % 2 == 0 ? new Color("b55648") : new Color("f0ce97");
                b.Polygon([new(x, 1.87f, -1.85f), new(x + .319f, 1.87f, -1.85f), new(x + .319f, 1.73f, -.91f), new(x, 1.73f, -.91f)], color, Vector3.Up);
                b.Polygon([new(x, 1.74f, -.91f), new(x + .319f, 1.74f, -.91f), new(x + .27f, 1.56f, -.88f), new(x + .06f, 1.56f, -.88f)], color, Vector3.Back);
            }
            b.RoundBox(new(0, .89f, -1.35f), new(1.2f, .16f, .43f), .025f, Planks);
            b.RoundBox(new(.16f, 1.03f, -1.36f), new(.55f, .16f, .22f), .035f, Stone);
            b.RoundBox(new(.18f, .67f, -1.36f), new(.36f, .43f, .26f), .03f, Planks);
        }
        return Bake(b);
    }
    public static MeshInstance3D NetFloat()
    {
        var b = new ActorGeometry();
        b.Sphere(new(0, .11f, 0), new(.21f, .23f, .20f), new("d58c54"), 8, 5);
        b.Ring(new(0, .15f, 0), .20f, .03f, new("f2d698"));
        b.Tube([new(0, .20f, 0), new(0, .64f, 0)], .023f, Planks, 6);
        b.Polygon([new(0, .62f, 0), new(.32f, .51f, .04f), new(0, .40f, 0)], new("e56b51"), Vector3.Back);
        return Bake(b);
    }
    public static MeshInstance3D BronzeBlank()
    {
        var b = new ActorGeometry();
        b.Tube([new(-.23f, .12f, 0), new(.24f, .12f, 0)], [.105f, .085f], new("db8e4e"), 9);
        b.Tube([new(-.23f, .12f, 0), new(-.16f, .12f, 0)], .145f, Gold, 9);
        return Bake(b);
    }
    public static MeshInstance3D CastingMould()
    {
        var b = new ActorGeometry();
        b.RoundBox(new(0, .035f, 0), new(.87f, .07f, .57f), .045f, Ink);
        b.RoundBox(new(0, .078f, 0), new(.55f, .022f, .22f), .01f, Rust);
        for (int i = -1; i <= 1; i += 2) b.RoundBox(new(i * .33f, .079f, 0), new(.08f, .022f, .48f), .01f, Gold);
        return Bake(b);
    }
    public static MeshInstance3D WindingPost()
    {
        var b = new ActorGeometry();
        b.RoundBox(new(0, .08f, 0), new(.58f, .16f, .55f), .035f, Stone);
        b.Tube([new(0, .12f, 0), new(0, .80f, 0)], [.17f, .13f], Planks, 8);
        for (int i = 0; i < 4; i++) b.Ring(new(0, .36f + i * .066f, 0), .18f, .039f, Gold);
        b.Tube([new(-.28f, .68f, 0), new(.28f, .68f, 0)], .054f, Gold, 7);
        return Bake(b);
    }

    static void Arch(ActorGeometry b)
    {
        Color[] masonry = [new("9a7975"), new("b18d80"), new("927d83"), new("b99581")];
        for (int i = 0; i < 9; i++)
        {
            float a = i * Mathf.Pi / 9 + .012f, c = (i + 1) * Mathf.Pi / 9 - .012f;
            Vector3 P(float angle, float radius, float z) => new(radius * MathF.Cos(angle), Floor + .64f + radius * MathF.Sin(angle), z - 3.52f);
            var front = new[] { P(a, 1, .18f), P(a, 1.4f, .18f), P(c, 1.4f, .18f), P(c, 1, .18f) };
            var back = front.Select(v => v - Vector3.Back * .49f).ToArray();
            var tint = masonry[i % 4];
            b.Polygon(front, tint, Vector3.Back);
            for (int j = 0; j < 4; j++) b.Polygon([front[j], front[(j + 1) % 4], back[(j + 1) % 4], back[j]], tint.Lightened(j == 1 ? .08f : 0), j == 1 ? Vector3.Up : Vector3.Right);
        }
        foreach (int sign in new[] { -1, 1 }) for (int j = 0; j < 2; j++)
            b.RoundBox(new(sign * 1.19f, Floor + .16f + j * .325f, -3.61f), new(.45f, .315f, .56f), .035f, masonry[(j + 1) % 4]);
    }

    static void Palm(ActorGeometry b, Vector3 p, Random rng)
    {
        var crown = p + new Vector3(.18f, 1.72f + rng.NextSingle() * .30f, 0);
        var bend = p + new Vector3(0, .84f, .04f);
        b.Tube([p, bend, crown], [.17f, .125f, .095f], new("967651"), 8);
        for (int i = 1; i < 6; i++) b.Ring(p.Lerp(crown, i / 7f), .135f - i * .005f, .016f, new("745e4a"));
        for (int i = 0; i < 9; i++)
        {
            float a = i * Mathf.Tau / 9 + rng.NextSingle() * .32f;
            var dir = new Vector3(MathF.Cos(a), 0, MathF.Sin(a));
            var side = new Vector3(-dir.Z, 0, dir.X);
            var mid = crown + dir * .56f + Vector3.Up * .25f;
            var tip = crown + dir * (.92f + rng.NextSingle() * .25f) - Vector3.Up * .19f;
            var leaf = new Color(i % 3 == 0 ? "a2ad45" : "769848");
            b.Polygon([crown, mid + side * .18f, tip, mid], leaf, Vector3.Up);
            b.Polygon([crown, mid, tip, mid - side * .17f], leaf.Darkened(.19f), Vector3.Up);
        }
    }
    public static MeshInstance3D SignalBell(bool rung)
    {
        var b = new ActorGeometry();
        foreach (int sign in new[] { -1, 1 })
            b.Tube([new(sign * .30f, 0, 0), new(sign * .28f, .87f, 0)], [.09f, .064f], Planks, 7);
        b.Tube([new(-.39f, .88f, 0), new(.39f, .88f, 0)], .076f, Planks.Darkened(.19f), 7);
        b.Tube([new(0, .91f, 0), new(0, .67f, 0)], .035f, Gold, 6);
        b.Loft([Ring(.23f, .37f), Ring(.23f, .42f), Ring(.16f, .48f), Ring(.14f, .65f), Ring(.08f, .70f)], [Gold, Gold, rung ? Teal : Rust, Gold]);
        b.Sphere(new(0, .34f, 0), Vector3.One * .062f, Gold);
        return Bake(b);
    }
}
