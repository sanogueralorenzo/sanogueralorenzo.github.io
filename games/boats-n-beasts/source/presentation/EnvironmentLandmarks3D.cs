using Godot;

namespace BoatsNBeasts;

// Independent world-size multipliers; the same options drive production and preview.
public sealed record LandmarkSizes(float Tavern = 1.25f, float Shipwreck = 1.35f, float SeaCave = 1.40f, float AncientArch = 1.25f)
{
    internal float ForKind(int kind)
    {
        float value = kind switch { 2 => Tavern, 3 => Shipwreck, 4 => SeaCave, 5 => AncientArch, _ => 1 };
        return float.IsFinite(value) ? Math.Clamp(value, .25f, 4f) : 1;
    }
}

public static partial class EnvironmentArt3D
{
    private static void PirateTavern(Sculptor art)
    {
        Color plaster = new("d3c9a6"), wood = new("775236"), cut = new("ad8050"), roof = new("ba763b"), glass = new("31555c");
        art.RoundedBox(new(0, .06f, 0), new(1.50f, .12f, .84f), .035f, new("a5a38c"));
        art.RoundedBox(new(0, .49f, 0), new(1.38f, .80f, .70f), .02f, plaster);
        for (int side = -1; side <= 1; side += 2)
        {
            art.Face(new(-side * .69f, .89f, side * .35f), new(side * .69f, .89f, side * .35f), new(0, 1.31f, side * .35f), plaster);
            for (int end = -1; end <= 1; end += 2)
                art.RoundedBox(new(side * .66f, .50f, end * .36f), new(.075f, .84f, .075f), .009f, wood);
            art.RoundedBox(new(0, .86f, side * .36f), new(1.42f, .07f, .075f), .009f, wood);
            art.Tube(new(-.69f, .87f, side * .37f), new(0, 1.33f, side * .37f), .029f, .029f, cut, 4);
            art.Tube(new(.69f, .87f, side * .37f), new(0, 1.33f, side * .37f), .029f, .029f, cut, 4);
        }
        art.RoundedBox(new(0, .15f, .37f), new(1.40f, .07f, .055f), .008f, wood);
        art.RoundedBox(new(-.24f, .37f, .375f), new(.29f, .54f, .045f), .008f, cut);
        for (int i = 0; i < 5; i++)
            art.RoundedBox(new(-.35f + i * .055f, .36f, .404f), new(.049f, .49f, .025f), .004f, new("426068"));
        art.Ellipsoid(new(-.16f, .35f, .429f), new(.015f, .015f, .01f), new("d0ad60"), 6, 4);
        Window(art, new(.37f, .56f, .378f), .18f, .25f, glass, cut);
        Window(art, new(0, 1.025f, .371f), .13f, .17f, glass, cut);
        var house = art.Transform;
        art.Transform = house * new Transform3D(Basis.FromEuler(new(0, Mathf.Pi / 2, 0)), new(.70f, .53f, -.04f));
        Window(art, Vector3.Zero, .20f, .26f, glass, cut);
        art.Transform = house;
        // Broad overlapping roof courses and seams, all cut from planar geometry.
        for (int side = -1; side <= 1; side += 2)
        {
            Vector3 Point(float t, float z, float lift = 0) => new(side * .83f * t, 1.38f - .49f * t + lift, -side * z);
            art.Quad(Point(0, -.46f), Point(1, -.46f), Point(1, .46f), Point(0, .46f), roof.Darkened(.15f));
            for (int row = 0; row < 3; row++) for (int column = 0; column < 5; column++)
            {
                float a = row / 3f, b = (row + 1) / 3f - .014f;
                float z = -.46f + column * .184f;
                art.Quad(Point(a, z, .008f), Point(b, z, .008f), Point(b, z + .177f, .008f), Point(a, z + .177f, .008f), roof.Lightened((row + column) % 3 * .025f));
            }
            art.Tube(Point(1, -.49f), Point(1, .49f), .026f, .026f, wood, 4);
        }
        art.Tube(new(0, 1.39f, -.49f), new(0, 1.39f, .49f), .035f, .035f, cut, 4);
        art.RoundedBox(new(-.42f, 1.38f, -.19f), new(.18f, .68f, .19f), .018f, plaster);
        art.RoundedBox(new(-.42f, 1.70f, -.19f), new(.23f, .06f, .24f), .012f, new("a5a38c"));
        art.RoundedBox(new(-.42f, 1.735f, -.19f), new(.10f, .01f, .11f), .003f, new("3e4644"));
        // Hanging tavern sign: a supported bracket, two links and a timber frame.
        art.Tube(new(.66f, 1.13f, .24f), new(1.07f, 1.42f, .24f), .017f, .017f, new("3d4c4e"), 6);
        for (int side = -1; side <= 1; side += 2)
            art.Tube(new(.99f + side * .075f, 1.39f, .24f), new(.99f + side * .075f, 1.28f, .24f), .007f, .007f, new("3d4c4e"), 5);
        art.RoundedBox(new(.99f, 1.11f, .24f), new(.30f, .37f, .05f), .018f, wood);
        NavyBanner(art, new(.99f, 1.11f, .273f), .25f, .31f);
        for (int i = 0; i < 2; i++)
            art.RoundedBox(new(-.24f, .07f - i * .025f, .45f + i * .09f), new(.38f, .06f, .12f), .012f, new("aaa78e"));
        Barrel(art, new(-.85f, .02f, .31f), .20f);
        Barrel(art, new(.82f, .02f, .40f), .22f);
    }

    private static void Shipwreck(Sculptor art)
    {
        Color wood = new("8e6037"), cut = new("b48a53"), dark = new("59432f");
        float[] xs = [-.94f, -.64f, -.20f, .24f, .70f];
        float[] widths = [.04f, .30f, .37f, .32f, .14f];
        float[] heights = [.77f, .64f, .55f, .42f, .20f];
        Vector3 Hull(int station, float t, int side, bool inside = false) => new(xs[station], .045f + heights[station] * t,
            side * (.035f + (widths[station] - .035f) * MathF.Sqrt(t) - (inside ? .025f : 0)));
        // Individual curved strakes stop at different stations around the torn stern.
        for (int side = -1; side <= 1; side += 2)
        {
            for (int row = 0; row < 4; row++) for (int station = 0; station < 4; station++)
            {
                if (station == 3 && row >= (side > 0 ? 2 : 3)) continue;
                float a = row / 4f, b = (row + 1) / 4f - .018f;
                void Plank(Vector3 p, Vector3 q, Vector3 r, Vector3 t, Color color)
                {
                    if (side > 0) art.Quad(p, q, r, t, color); else art.Quad(t, r, q, p, color);
                }
                Plank(Hull(station, a, side), Hull(station + 1, a, side), Hull(station + 1, b, side), Hull(station, b, side), wood.Lightened(row % 2 * .05f));
                Plank(Hull(station, b, side, true), Hull(station + 1, b, side, true), Hull(station + 1, a, side, true), Hull(station, a, side, true), cut.Darkened(.10f));
                art.Tube(Hull(station, b, side), Hull(station + 1, b, side), .011f, .011f, cut, 4);
            }
            for (int station = 1; station < 4; station++)
            {
                var foot = new Vector3(xs[station], .08f, 0);
                var bend = new Vector3(xs[station], .22f, side * widths[station] * .68f);
                art.Tube(foot, bend, .027f, .027f, dark, 4);
                art.Tube(bend, Hull(station, .94f, side, true), .027f, .022f, dark, 4);
            }
        }
        for (int i = 0; i < 6; i++)
            art.RoundedBox(new(-.59f + i * .19f, .085f, 0), new(.18f, .045f, .32f), .008f, cut.Darkened(i % 2 * .06f));
        art.Tube(new(-.94f, .055f, 0), new(-.94f, .83f, 0), .04f, .026f, cut, 5);
        art.Tube(new(.22f, .08f, -.04f), new(.44f, 1.39f, -.04f), .038f, .029f, wood, 6);
        art.Tube(new(-.14f, 1.15f, .015f), new(.86f, 1.30f, .015f), .026f, .021f, cut, 6);
        for (int i = 0; i < 3; i++)
            art.Tube(new(.38f, 1.20f + i * .034f, -.04f), new(.45f, 1.20f + i * .034f, -.04f), .036f, .036f, dark, 6);
        // Uneven cloth polygons have real gaps and a torn lower hem.
        Vector3[][] scraps = [
            [new(-.10f,1.16f,.04f),new(-.06f,.84f,.08f),new(.04f,.96f,.10f),new(.12f,.80f,.10f),new(.24f,1.21f,.04f)],
            [new(.46f,1.24f,.04f),new(.43f,.82f,.12f),new(.56f,.92f,.12f),new(.67f,.79f,.10f),new(.82f,1.29f,.04f)]
        ];
        foreach (var scrap in scraps) for (int i = 1; i < scrap.Length - 1; i++)
            art.Face(scrap[0], scrap[i], scrap[i + 1], new("d8d0ab"));
        var wreck = art.Transform;
        for (int i = 0; i < 3; i++)
        {
            art.Transform = wreck * new Transform3D(Basis.FromEuler(new(0, -.5f + i * .4f, .05f)), new(.57f + i * .10f, .045f, .40f + i * .09f));
            art.RoundedBox(Vector3.Zero, new(.43f - i * .06f, .045f, .085f), .006f, wood.Lightened(i * .04f));
        }
        art.Transform = wreck;
    }

    private static void SeaCave(Sculptor art, uint seed)
    {
        // An actual recessed shell: the mouth is empty, with side walls, ceiling,
        // a shaded floor and a rear wall well behind the facade.
        Vector2[] outer = [new(-.84f,.02f),new(-.81f,.67f),new(-.58f,1.18f),new(-.17f,1.43f),new(.36f,1.33f),new(.76f,.88f),new(.84f,.02f)];
        Vector2[] inner = [new(-.43f,.02f),new(-.45f,.48f),new(-.30f,.80f),new(0,.98f),new(.28f,.82f),new(.44f,.47f),new(.43f,.02f)];
        Color rock = new("77868a"), recess = new("354d52");
        Vector3 Front(Vector2 p) => new(p.X, p.Y, .38f);
        Vector3 Back(Vector2 p) => new(p.X * .82f, p.Y * .84f, -.54f);
        for (int i = 0; i < outer.Length - 1; i++)
        {
            var middle = (Front(outer[i]) + Front(outer[i + 1]) + Front(inner[i]) + Front(inner[i + 1])) * .25f;
            middle.Z += .055f + i % 2 * .055f;
            art.Face(Front(outer[i]), middle, Front(outer[i + 1]), rock.Lightened(i % 3 * .025f));
            art.Face(Front(outer[i + 1]), middle, Front(inner[i + 1]), rock.Darkened(.04f));
            art.Face(Front(inner[i + 1]), middle, Front(inner[i]), rock.Darkened(.10f));
            art.Face(Front(inner[i]), middle, Front(outer[i]), rock);
            art.Quad(Back(outer[i + 1]), Back(outer[i]), Front(outer[i]), Front(outer[i + 1]), rock.Darkened(i % 2 * .045f));
            art.Quad(Back(inner[i]), Back(inner[i + 1]), Front(inner[i + 1]), Front(inner[i]), recess.Lightened(i % 3 * .02f));
            art.Face(new(0, .34f, -.55f), Back(inner[i + 1]), Back(inner[i]), recess.Darkened(.27f));
            art.Quad(Back(outer[i + 1]), Back(inner[i + 1]), Back(inner[i]), Back(outer[i]), rock.Darkened(.12f));
        }
        art.Face(new(0, .34f, -.55f), Back(inner[0]), Back(inner[^1]), recess.Darkened(.27f));
        art.Quad(new(-.43f,.025f,.43f),new(.43f,.025f,.43f),new(.35f,.025f,-.55f),new(-.35f,.025f,-.55f), new("666c57"));
        for (int side = -1; side <= 1; side += 2)
        {
            art.Boulder(new(side * .76f, .20f, .30f), new(.39f, .44f, .46f), rock, seed + (uint)(side + 3));
            HangingMoss(art, new(side * .56f, 1.10f, .43f), .47f, seed + (uint)(side + 8));
        }
        art.Boulder(new(-.52f, 1.13f, -.10f), new(.50f, .45f, .65f), rock, seed + 15);
        art.Boulder(new(.58f, .92f, -.10f), new(.40f, .60f, .55f), rock, seed + 17);
        art.Boulder(new(.05f, 1.38f, -.12f), new(.37f, .12f, .28f), Leaf, seed + 19);
    }

    private static void AncientArch(Sculptor art, uint seed)
    {
        Color stone = new("7b8884"), pale = new("b7bca1");
        var arch = art.Transform;
        for (int side = -1; side <= 1; side += 2)
        {
            art.RoundedBox(new(side * .53f, .06f, 0), new(.43f, .13f, .47f), .028f, stone.Darkened(.12f));
            for (int block = 0; block < 3; block++)
            {
                art.Transform = arch * new Transform3D(Basis.FromEuler(new(0, side * (block - 1) * .024f, 0)), new(side * .53f, .23f + block * .29f, 0));
                art.RoundedBox(Vector3.Zero, new(.34f, .28f, .37f), .023f, stone.Lightened(block % 2 * .045f));
            }
            art.Transform = arch;
            for (int mark = 0; mark < 2; mark++) Glyph(new(side * .53f, .37f + mark * .39f, .199f), .095f);
            HangingMoss(art, new(side * .61f, 1.18f, .15f), .32f, seed + (uint)(side + 9));
            art.Boulder(new(side * .76f, .11f, .19f), new(.23f, .24f, .26f), stone, seed + (uint)(side + 2));
        }
        for (int i = 0; i <= 6; i++)
        {
            float angle = i * Mathf.Pi / 6;
            art.Transform = arch * new Transform3D(Basis.FromEuler(new(0, 0, angle - Mathf.Pi / 2)), new(Mathf.Cos(angle) * .53f, .97f + Mathf.Sin(angle) * .53f, 0));
            art.RoundedBox(Vector3.Zero, new(.30f, .31f, .39f), .026f, stone.Lightened(i % 3 * .035f));
        }
        art.Transform = arch;
        Glyph(new(0, 1.49f, .202f), .075f);
        art.Boulder(new(-.21f, 1.56f, -.02f), new(.30f, .10f, .24f), Leaf, seed + 21);
        void Glyph(Vector3 center, float radius)
        {
            for (int i = 0; i < 20; i++)
            {
                float a = i * Mathf.Tau * 1.25f / 20, b = (i + 1) * Mathf.Tau * 1.25f / 20;
                float ra = radius * (1 - i / 26f), rb = radius * (1 - (i + 1) / 26f);
                art.Tube(center + new Vector3(Mathf.Cos(a) * ra, Mathf.Sin(a) * ra, 0), center + new Vector3(Mathf.Cos(b) * rb, Mathf.Sin(b) * rb, 0), .008f, .008f, pale, 4);
            }
        }
    }

    private static void HangingMoss(Sculptor art, Vector3 at, float length, uint seed)
    {
        for (int i = 0; i < 4; i++)
        {
            var p = at + new Vector3(Mathf.Sin(i * 1.3f) * .035f, -length * i / 4, .02f);
            var next = at + new Vector3(Mathf.Sin((i + 1) * 1.3f) * .035f, -length * (i + 1) / 4, .025f);
            art.Tube(p, next, .010f, .007f, Leaf.Darkened(.10f), 4);
            art.Boulder(p + new Vector3(i % 2 == 0 ? -.035f : .035f, 0, .018f), new(.10f, .10f, .035f), Leaf.Lightened(i % 2 * .08f), seed + (uint)i);
        }
    }
}
