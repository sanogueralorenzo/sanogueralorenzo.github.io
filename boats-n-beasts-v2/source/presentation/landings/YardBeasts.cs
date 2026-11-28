using BoatsNBeasts.Core;
using Godot;

namespace BoatsNBeasts;

internal static class YardBeasts
{
    static readonly Color Ash = new("484352"), Brass = new("e6af69"), Ivory = new("efe0b4"), Eye = new("ffd890");
    static readonly Dictionary<(IslandClimate, YardBeast, string), ArrayMesh> shapes = [];
    public static MeshInstance3D Make(LandingRegion region, YardBeast kind, CampaignOrder order)
    {
        var name = order.Boss;
        var key = (region.Climate, kind, kind == YardBeast.Guardian ? order.Id : "");
        if (!shapes.TryGetValue(key, out var mesh))
        {
            var b = new ActorGeometry(); Color hide = new(region.Rock), warm = new(region.Cloth), light = new(region.Trim);
            if (kind != YardBeast.Guardian) Watcher(b, kind, hide, warm, light);
            else if (order.Island.Length > 0 && GuardianBreed.Named(name) is var breed && breed != GuardianForm.Regional)
            {
                switch (breed)
                {
                    case GuardianForm.Cat: Hooved(b, hide, warm, light, false, true); break;
                    case GuardianForm.Bird: Heron(b, hide, warm, light); break;
                    case GuardianForm.Insect: Hornet(b, hide, light); break;
                    case GuardianForm.Drake: Serpent(b, hide, light, warm, true); break;
                    case GuardianForm.Serpent: Serpent(b, hide, warm, light, false); break;
                    case GuardianForm.Shell: Beetle(b, warm, light, hide); break;
                    case GuardianForm.Weaver: Spider(b, hide, warm, light); break;
                    default: Clockman(b, warm, light); break;
                }
            }
            else if (name == "Stamp Beetle") Beetle(b, warm, Brass, hide);
            else if (name == "Freezer Dog") Hooved(b, hide, new("7394a1"), Ivory, false, true);
            else if (name == "Cradle Hornet") Hornet(b, hide, light);
            else if (name == "Tally Jack") Clockman(b, warm, light);
            else if (name == "Ward Lamprey" || name == "The Plumb Serpent") Serpent(b, hide, warm, light, name == "The Plumb Serpent");
            else if (name == "The Brass Balance") Balance(b, hide, light);
            else switch (region.Climate)
                {
                    case IslandClimate.Kiln: Hooved(b, hide, warm, light, false, false); break;
                    case IslandClimate.Delta: Heron(b, hide, Ivory, light); break;
                    case IslandClimate.Orchard: Moth(b, hide, warm, light); break;
                    case IslandClimate.Shelf: Walrus(b, hide, warm, Ivory); break;
                    case IslandClimate.Loom: Spider(b, hide, warm, light); break;
                    case IslandClimate.Reef: Nautilus(b, hide, warm, light); break;
                    case IslandClimate.Court: Hooved(b, hide, warm, light, false, true); break;
                    case IslandClimate.Stars: Hooved(b, hide, warm, light, true, false); break;
                }
            if (kind == YardBeast.Guardian && order.Island.Length > 0)
            {
                int signature = order.Id.Sum(c => (int)c);
                int count = 2 + signature % 4;
                for (int i = 0; i < count; i++)
                {
                    float x = (i - (count - 1) * .5f) * .128f;
                    b.Tube([new(x, .99f, .03f), new(x, 1.12f + (i % 2) * .10f, .14f), new(x, 1.16f + (signature % 5) * .045f, .29f)],
                        [.060f, .045f, .008f], i % 2 == 0 ? light : warm, 6);
                }
            }
            mesh = b.Mesh(DioramaSurface.Material); shapes.Add(key, mesh);
        }
        return new MeshInstance3D { Mesh = mesh };
    }
    static void EyePair(ActorGeometry b, float half, float y, float z)
    {
        foreach (int side in new[] { -1, 1 })
        {
            b.Sphere(new(side * half, y, z), new(.095f, .084f, .070f), Ash, 8, 5);
            b.Sphere(new(side * half, y + .007f, z - .047f), new(.066f, .054f, .031f), Eye, 7, 4);
        }
    }
    static void Hooved(ActorGeometry b, Color hide, Color trim, Color light, bool hart, bool hound)
    {
        float y = hart ? 1.00f : .82f;
        b.Sphere(new(0, y, .16f), new(hound ? .45f : .62f, hart ? .44f : .53f, .96f), hide);
        b.Sphere(new(0, y + .17f, -.42f), new(.55f, .58f, .50f), hide.Lightened(.07f));
        b.Sphere(new(0, y + .23f, -.89f), new(.42f, .38f, .45f), trim);
        b.Sphere(new(0, y + .13f, -1.19f), new(.32f, .22f, .30f), hide);
        EyePair(b, .31f, y + .31f, -1.14f);
        foreach (int s in new[] { -1, 1 })
        {
            foreach (int e in new[] { -1, 1 })
            {
                float x = s * .37f, z = e * .56f;
                b.Tube([new(x, y, z), new(x * 1.13f, .40f, z + (e > 0 ? .13f : -.03f)), new(x * 1.20f, .095f, z - .06f)],
                      [.21f, hart ? .086f : .14f, .11f], hide, 7);
                b.RoundBox(new(x * 1.20f, .09f, z - .105f), new(.24f, .15f, .28f), .035f, Brass);
            }
            if (hound)
            {
                b.Polygon([new(s * .26f, y + .48f, -.98f), new(s * .46f, y + .84f, -.82f), new(s * .39f, y + .34f, -.71f)], trim, Vector3.Forward);
                b.Tube([new(s * .23f, y + .12f, -1.33f), new(s * .22f, y - .10f, -1.39f)], [.060f, .010f], Ivory);
            }
            else
            {
                b.Tube([new(s * .29f, y + .46f, -.84f), new(s * .64f, y + .53f, -.78f), new(s * .91f, y + .75f, -.68f), new(s * (hart ? 1.00f : .83f), y + (hart ? 1.25f : .93f), -.61f)],
                    [.155f, .13f, .070f, .011f], hart ? light : Ivory, 8);
                if (hart) for (int n = 0; n < 2; n++)
                    b.Tube([new(s * (.65f + .16f * n), y + .59f + .15f * n, -.73f), new(s * (.51f + .18f * n), y + 1.03f + .21f * n, -.83f)], [.073f, .009f], Ivory, 6);
            }
            b.Tube([new(s * .5f, y + .39f, -.49f), new(s * .61f, y + .02f, -.47f), new(s * .45f, y - .25f, -.46f)], .067f, light, 7);
            for (int n = 0; n < 2; n++)
            {
                float x = s * (.62f + .09f * n);
                b.Tube([new(x, y + .12f, -.36f), new(x, y - .16f, -.33f)], .022f, Brass, 6);
                b.RoundBox(new(x, y - .16f, -.34f), new(.069f, .045f, .09f), .008f, Brass);
            }
        }
        b.Tube([new(0, y + .17f, .89f), new(.10f, y + .28f, 1.26f), new(.28f, hound ? y + .62f : y - .05f, 1.39f)], [.10f, .065f, .04f], hide, 7);
        if (!hart && !hound)
        {
            b.RoundBox(new(0, y + .56f, .08f), new(1.37f, .18f, .27f), .055f, Brass);
            for (int i = 0; i < 3; i++) b.RoundBox(new(0, y + .53f, .35f + i * .15f), new(.66f, .20f, .08f), .025f, trim);
        }
    }
    static void Heron(ActorGeometry b, Color hide, Color feather, Color light)
    {
        b.Sphere(new(0, 1.13f, .16f), new(.48f, .44f, .72f), feather);
        b.Tube([new(0, 1.15f, -.23f), new(0, 1.49f, -.57f), new(0, 1.88f, -.38f), new(0, 1.90f, -.80f)], [.22f, .17f, .135f, .17f], feather);
        b.Sphere(new(0, 1.91f, -.77f), new(.20f, .16f, .23f), feather);
        b.Tube([new(0, 1.88f, -.90f), new(0, 1.82f, -1.64f)], [.130f, .008f], light, 6); EyePair(b, .14f, 1.94f, -.875f);
        foreach (int s in new[] { -1, 1 })
        {
            b.Tube([new(s * .23f, 1.0f, 0), new(s * .32f, .43f, .16f), new(s * .31f, .06f, -.1f)], .059f, light, 7);
            for (int j = -1; j <= 1; j++) b.Tube([new(s * .31f, .06f, -.1f), new(s * .31f + j * .14f, .025f, -.37f)], [.038f, .009f], light, 6);
            for (int i = 0; i < 4; i++) b.Tube([new(s * .32f, 1.32f, -.13f), new(s * (.48f + .07f * i), 1.19f, .33f), new(s * (.34f + .12f * i), 1.07f, .92f + i * .05f)], [.11f, .13f, .012f], hide.Lightened(.07f * i), 6);
        }
    }
    static void Moth(ActorGeometry b, Color hide, Color wing, Color light)
    {
        b.Sphere(new(0, .77f, 0), new(.27f, .26f, .82f), hide); b.Sphere(new(0, .91f, -.60f), new(.35f, .28f, .29f), light); EyePair(b, .22f, .94f, -.80f);
        foreach (int s in new[] { -1, 1 })
        {
            var hub = new Vector3(s * .17f, .79f, -.2f);
            var points = new[] { hub, new(s * 1.76f, 1.18f, -1.05f), new(s * 1.61f, .92f, -.28f), new(s * 1.34f, .83f, .16f), new(s * .91f, .68f, .91f), new(s * .51f, .70f, .82f) };
            b.Polygon(points, wing, Vector3.Up);
            foreach (var end in points.Skip(1)) b.Tube([hub + Vector3.Up * .02f, end], .023f, light, 5);
            b.Sphere(new(s * 1.15f, .98f, -.39f), new(.21f, .055f, .19f), light);
            b.Tube([new(s * .17f, 1.05f, -.63f), new(s * .36f, 1.30f, -.88f), new(s * .48f, 1.23f, -1.04f)], [.041f, .031f, .012f], Brass, 6);
        }
    }
    static void Walrus(ActorGeometry b, Color hide, Color trim, Color ivory)
    {
        b.Sphere(new(0, .59f, .17f), new(.85f, .61f, .98f), hide); b.Sphere(new(0, .89f, -.63f), new(.51f, .45f, .45f), hide.Lightened(.09f));
        b.Sphere(new(0, .75f, -.97f), new(.38f, .22f, .22f), trim); EyePair(b, .32f, .99f, -.91f);
        foreach (int s in new[] { -1, 1 })
        {
            b.Tube([new(s * .25f, .73f, -1.04f), new(s * .28f, .43f, -1.12f), new(s * .23f, .19f, -1.17f)], [.092f, .071f, .009f], ivory);
            b.Sphere(new(s * .64f, .16f, -.34f), new(.47f, .15f, .31f), trim);
            b.Sphere(new(s * .38f, .15f, .90f), new(.39f, .125f, .42f), hide);
        }
        b.RoundBox(new(0, 1.23f, .23f), new(.61f, .32f, .56f), .04f, trim); b.Tube([new(0, 1.36f, .32f), new(0, 1.71f, .32f)], .10f, Brass, 8);
    }
    static void Spider(ActorGeometry b, Color hide, Color trim, Color silk)
    {
        b.Sphere(new(0, .60f, .28f), new(.51f, .39f, .72f), trim); b.Sphere(new(0, .58f, -.38f), new(.35f, .27f, .36f), hide); EyePair(b, .19f, .64f, -.70f);
        foreach (int s in new[] { -1, 1 }) for (int i = 0; i < 4; i++)
        {
            float z = -.48f + i * .32f;
            b.Tube([new(s * .26f, .64f, z), new(s * (.96f + i * .03f), .91f, z - .08f), new(s * (1.29f + i * .035f), .045f, z + (i - 1.5f) * .30f)], [.088f, .065f, .022f], i % 2 == 0 ? trim : silk, 7);
        }
    }
    static void Nautilus(ActorGeometry b, Color hide, Color shell, Color light)
    {
        b.Sphere(new(0, .90f, .15f), new(.49f, .80f, .81f), shell); b.Sphere(new(0, .44f, -.44f), new(.49f, .33f, .52f), hide); EyePair(b, .32f, .52f, -.78f);
        foreach (int s in new[] { -1, 1 })
        {
            Vector3[] path = Enumerable.Range(0, 24).Select(i => { float a = i * .32f, r = .08f + i * .024f; return new Vector3(s * .43f, .9f + MathF.Sin(a) * r, .15f + MathF.Cos(a) * r); }).ToArray(); b.Tube(path, .045f, light, 6);
            for (int i = 0; i < 3; i++) b.Tube([new(s * .19f, .35f, -.63f), new(s * (.40f + i * .17f), .13f, -.83f), new(s * (.58f + i * .21f), .22f, -.95f + i * .18f)], [.105f, .077f, .018f], hide.Lightened(i * .07f), 6);
        }
    }
    static void Beetle(ActorGeometry b, Color shell, Color trim, Color hide)
    {
        Spider(b, hide, trim, shell); b.Sphere(new(0, .85f, .16f), new(.72f, .43f, .86f), shell);
        b.Tube([new(0, 1.25f, -.34f), new(0, 1.29f, .18f), new(0, 1.12f, .76f)], .035f, trim);
        b.Tube([new(0, .75f, -.58f), new(0, 1.1f, -.91f), new(0, 1.34f, -.73f)], [.17f, .10f, .02f], hide);
    }
    static void Hornet(ActorGeometry b, Color hide, Color light)
    {
        b.Sphere(new(0, .74f, .46f), new(.41f, .38f, .68f), light);
        for (int i = 0; i < 3; i++) b.Sphere(new(0, .74f, .15f + i * .25f), new(.39f - i * .045f, .37f - i * .03f, .105f), hide);
        b.Sphere(new(0, .86f, -.30f), new(.38f, .39f, .41f), hide);
        b.Sphere(new(0, .94f, -.74f), new(.31f, .21f, .23f), light); EyePair(b, .22f, .97f, -.91f);
        foreach (int sign in new[] { -1, 1 })
            for (int i = 0; i < 2; i++) b.Polygon([new(sign*.22f,1.05f,-.24f),new(sign*(1.25f+i*.15f),1.26f,-.48f+i*.62f),
                new(sign*(1.53f-i*.15f),1.19f,-.15f+i*.64f),new(sign*.46f,.97f,.12f+i*.21f)], i == 0 ? Ivory : light, Vector3.Up);
        b.Tube([new(0, .74f, .92f), new(0, .61f, 1.37f)], [.18f, .01f], hide);
    }
    static void Clockman(ActorGeometry b, Color coat, Color trim)
    {
        b.RoundBox(new(0, .81f, 0), new(.69f, .72f, .47f), .12f, coat);
        b.Sphere(new(0, .89f, -.24f), new(.26f, .28f, .08f), Ivory);
        b.Tube([new(0, .89f, -.33f), new(.13f, 1.04f, -.33f)], .024f, Ash);
        b.Sphere(new(0, 1.40f, 0), new(.32f, .28f, .25f), trim); EyePair(b, .18f, 1.45f, -.20f);
        foreach (int sign in new[] { -1, 1 })
        {
            b.Tube([new(sign * .29f, 1.04f, 0), new(sign * .73f, 1.23f, .02f), new(sign * .97f, .93f, -.18f)], [.11f, .105f, .078f], trim);
            b.Sphere(new(sign * .97f, .93f, -.18f), new(.21f, .15f, .17f), coat);
            b.Tube([new(sign * .24f, .5f, 0), new(sign * .29f, .12f, -.04f)], .11f, trim);
            b.RoundBox(new(sign * .31f, .11f, -.10f), new(.30f, .18f, .37f), .045f, Ash);
        }
    }
    static void Serpent(ActorGeometry b, Color hide, Color stripe, Color light, bool plumb)
    {
        Vector3[] spine = [new(.83f,.13f,.93f),new(.18f,.28f,.71f),new(-.57f,.32f,1.04f),new(-.73f,.36f,.40f),
            new(-.22f,.44f,.18f),new(.23f,.71f,-.18f),new(.08f,1.18f,-.59f),new(-.12f,1.38f,-.88f)];
        b.Tube(spine, [.09f, .18f, .24f, .25f, .27f, .25f, .22f, .29f], hide, 10);
        b.Sphere(spine[^1], new(.35f, .25f, .34f), stripe); EyePair(b, .19f, 1.45f, -1.08f);
        if (plumb) b.Crystal(new(.90f, .25f, .98f), new(.18f, .31f, .18f), light);
        else
        {
            for (int i = 0; i < 9; i++) { float a = i * Mathf.Tau / 9; var p = new Vector3(-.12f + MathF.Cos(a) * .20f, 1.37f + MathF.Sin(a) * .16f, -1.15f); b.Tube([p, p + Vector3.Forward * .13f], [.032f, .008f], Ivory, 6); }
            b.Sphere(new(-.12f, 1.37f, -1.16f), new(.15f, .13f, .04f), Ash);
        }
    }
    static void Balance(ActorGeometry b, Color hide, Color light)
    {
        b.Sphere(new(0, .27f, 0), new(.52f, .29f, .42f), hide);
        b.Tube([new(0, .22f, 0), new(0, 1.62f, 0)], [.20f, .09f], light, 8);
        b.Tube([new(-1.03f, 1.49f, 0), new(1.03f, 1.68f, 0)], .068f, light);
        foreach (int sign in new[] { -1, 1 })
        {
            float high = 1.57f + sign * .09f;
            for (int j = -1; j <= 1; j += 2) b.Tube([new(sign * .90f, high, 0), new(sign * .90f + j * .26f, .78f, 0)], .026f, light);
            b.Sphere(new(sign * .90f, .73f, 0), new(.39f, .11f, .34f), light);
            b.Crystal(new(sign * .90f, .92f, 0), new(.19f, .24f, .19f), hide);
        }
        b.Sphere(new(0, 1.40f, -.07f), new(.20f, .21f, .16f), hide); EyePair(b, .125f, 1.42f, -.19f);
    }
    static void Watcher(ActorGeometry b, YardBeast kind, Color hide, Color coat, Color trim)
    {
        float bulk = kind == YardBeast.Porter ? .38f : .26f;
        b.Sphere(new(0, .47f, 0), new(bulk, .34f, .24f), coat);
        b.RoundBox(new(0, .79f, -.025f), new(.39f, .27f, .30f), .055f, hide);
        foreach (int s in new[] { -1, 1 })
        {
            b.Tube([new(s * .13f, .38f, 0), new(s * .17f, .075f, -.014f)], .08f, hide, 6);
            b.RoundBox(new(s * .17f, .065f, -.062f), new(.17f, .12f, .23f), .026f, trim);
            b.Tube([new(s * bulk * .8f, .55f, 0), new(s * (bulk + .12f), .30f, -.12f)], .071f, hide, 6);
            b.RoundBox(new(s * .10f, .80f, -.186f), new(.064f, .040f, .025f), .01f, Eye);
        }
        if (kind == YardBeast.Slinger) b.Tube([new(-.23f, .33f, -.04f), new(-.36f, 1.13f, -.17f)], [.075f, .115f], Brass, 8);
        if (kind == YardBeast.Porter) b.RoundBox(new(0, .48f, -.28f), new(.76f, .54f, .11f), .065f, trim);
        if (kind == YardBeast.Skater) b.Polygon([new(-.10f, .88f, .03f), new(0, 1.26f, .38f), new(.16f, .78f, .05f)], trim, Vector3.Up);
        if (kind == YardBeast.Scrapper) b.Tube([new(.32f, .37f, -.11f), new(.43f, .62f, -.47f)], [.052f, .011f], Ivory, 5);
    }
}
