using Godot;

namespace BoatsNBeasts;

internal static class ShoreBeach
{
    public static void Paint(ActorGeometry geometry, Vector3[] rim, Color rock, Color ground, int seed)
    {
        var random = new Random(seed);
        var sand = ground.Lerp(new("efc792"), .61f); var wet = ground.Lerp(new("93b4a0"), .53f);
        var shore = new List<Vector3>();
        for (int i = 0; i < rim.Length; i++)
        {
            var first = rim[i] with { Y = 0 }; var end = rim[(i + 1) % rim.Length] with { Y = 0 };
            int strokes = Math.Max(1, (int)MathF.Ceiling(first.DistanceTo(end) / .38f));
            for (int j = 0; j < strokes; j++) shore.Add(first.Lerp(end, j / (float)strokes));
        }
        int count = shore.Count;
        var strata = new Vector3[6, count];
        for (int i = 0; i < count; i++)
        {
            var p = shore[i]; var d = p.Normalized(); float wave = MathF.Sin(i * .31f + seed % 17) * .12f + MathF.Sin(i * .78f) * .06f;
            float toe = .12f + p.Length() * .083f;
            strata[0, i] = p + d * (toe - .10f) + Vector3.Up * .020f;
            strata[1, i] = p + d * (toe + .02f + wave) + Vector3.Up * .060f;
            strata[2, i] = p + d * (toe + .25f + wave * 2) + Vector3.Up * .036f;
            strata[3, i] = p + d * (toe + .34f + wave * 2) + Vector3.Up * .027f;
            strata[4, i] = p + d * (toe + .49f + wave * 2.5f) + Vector3.Up * .020f;
            strata[5, i] = p + d * (toe + .60f + wave * 3 + .20f * MathF.Sin(i * .16f)) + Vector3.Up * .010f;
        }
        for (int i = 0; i < count; i++)
        {
            int j = (i + 1) % count; float fleck = random.NextSingle();
            for (int k = 0; k < 5; k++)
            {
                Color tone = k switch { 0 => rock.Lerp(sand, .48f), 1 => sand, 2 => wet, 3 => i % 13 < 7 ? new("a7d5c1") : new("72b3a3"), _ => new("459c99") };
                geometry.Polygon([strata[k, i], strata[k, j], strata[k + 1, j], strata[k + 1, i]], tone.Lightened(fleck * .037f), Vector3.Up);
            }
            if (i % 7 is 2 or 3 or 4)
            {
                var a = strata[3, i] + Vector3.Up * .008f; var b = strata[3, j] + Vector3.Up * .008f;
                geometry.Polygon([a, b, b.Lerp(strata[4, j], .16f), a.Lerp(strata[4, i], .20f)], new("eddcbd"), Vector3.Up);
            }
            if (i % 29 is >= 6 and <= 10)
            {
                var a = strata[4, i] + Vector3.Up * .009f; var z = strata[4, j] + Vector3.Up * .009f; var u = (a with { Y = 0 }).Normalized(); var v = (z with { Y = 0 }).Normalized();
                float width = .025f + .026f * MathF.Sin((i % 29 - 6) * Mathf.Pi / 4);
                geometry.Polygon([a + u * .07f, z + v * .07f, z + v * (.07f + width), a + u * (.07f + width)], new("c8e8d9"), Vector3.Up);
            }
            if (i % 17 == 0)
            {
                var p = strata[1, i]; var d = (p with { Y = 0 }).Normalized();
                var mid = p - d * .17f + Vector3.Up * .16f;
                geometry.Sphere(mid, new(.25f + .12f * fleck, .18f + .21f * fleck, .25f), rock.Lerp(ground, .22f), 7, 4);
                var tip = mid - d * .22f + Vector3.Up * .09f;
                for (int blade = 0; blade < 4; blade++)
                {
                    float angle = blade * 1.67f + i; var leaf = new Vector3(MathF.Sin(angle), 0, MathF.Cos(angle)); var side = leaf.Cross(Vector3.Up);
                    geometry.Polygon([tip - side * .041f, tip + leaf * .19f + Vector3.Up * .17f, tip + side * .046f], blade % 2 == 0 ? new("8aa169") : new("759676"), Vector3.Up);
                }
            }
            if (i % 11 == 0)
            {
                var p = strata[2, i]; float scale = .12f + fleck * .13f;
                geometry.Sphere(p + Vector3.Up * .040f, new(scale, .095f + fleck * .12f, scale * .78f), rock.Lerp(sand, .26f), 6, 4);
                var q = p + new Vector3(.19f, .015f, .08f);
                geometry.Sphere(q, new(.084f, .054f, .071f), rock.Lerp(ground, .4f), 6, 3);
            }
        }
    }
}
