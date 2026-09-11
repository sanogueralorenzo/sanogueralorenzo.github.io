using Godot;

namespace BoatsNBeasts;

// Independent world-size multipliers; the same options drive production and preview.
public sealed record LandmarkSizes(float Tavern = 1.25f, float Shipwreck = 1.35f, float SeaCave = 1.40f, float AncientArch = 1.25f, float Lighthouse = 1.25f, float MarketStall = 1.35f, float Windmill = 1.25f)
{
    internal float ForKind(int kind)
    {
        float value = kind switch { 2 => Tavern, 3 => Shipwreck, 4 => SeaCave, 5 => AncientArch, 6 => Lighthouse, 7 => MarketStall, 8 => Windmill, _ => 1 };
        return float.IsFinite(value) ? Math.Clamp(value, .25f, 4f) : 1;
    }
}

public static partial class EnvironmentArt3D
{
    private static void PirateTavern(Sculptor art)
    {
        Color plaster = new("c4b58e"), wood = new("765334"), cut = new("ad8050"), roof = new("d67a36"), glass = new("31555c"), iron = new("394b4c");
        var house = art.Transform;
        // A broad main hall and a lower cross-gabled wing give the tavern its silhouette.
        art.RoundedBox(new(-.15f, .065f, 0), new(1.50f, .13f, 1.02f), .025f, new("a5a38c"));
        art.RoundedBox(new(-.15f, .59f, 0), new(1.38f, .98f, .90f), .018f, plaster);
        art.RoundedBox(new(.74f, .065f, 0), new(.70f, .13f, .79f), .025f, new("a5a38c"));
        art.RoundedBox(new(.74f, .52f, 0), new(.64f, .84f, .68f), .015f, plaster);
        for (int side = -1; side <= 1; side += 2)
        {
            float z = side * .46f;
            art.Face(new(-.15f - side * .69f, 1.08f, z), new(-.15f + side * .69f, 1.08f, z), new(-.15f, 1.83f, z), plaster);
            for (int end = -1; end <= 1; end += 2)
                art.RoundedBox(new(-.15f + end * .665f, .59f, z), new(.09f, 1.02f, .085f), .009f, wood);
            art.RoundedBox(new(-.15f, 1.045f, z), new(1.44f, .095f, .09f), .008f, wood);
            art.RoundedBox(new(-.15f, .17f, z), new(1.42f, .09f, .075f), .008f, wood);
            art.RoundedBox(new(-.15f, 1.38f, z), new(.055f, .60f, .065f), .007f, wood);
            art.RoundedBox(new(1.055f, .52f, side * .335f), new(.085f, .88f, .085f), .008f, wood);
            art.RoundedBox(new(.79f, .92f, side * .35f), new(.60f, .085f, .075f), .008f, wood);
            art.RoundedBox(new(.79f, .17f, side * .35f), new(.60f, .08f, .07f), .008f, wood);
        }
        void WeatheredWall(Vector3 center, float width, float height)
        {
            const int columns = 6, rows = 5;
            Vector3 Point(int x, int y) => center + new Vector3((x / (float)columns - .5f) * width, (y / (float)rows - .5f) * height, 0);
            Color Tone(int x, int y)
            {
                float u = x / (float)columns, v = y / (float)rows;
                float dampHeight = .25f + .10f * Mathf.Sin(u * 11 + center.X * 7);
                float damp = MathF.Max(0, 1 - v / dampHeight);
                float mottling = .035f * (1 + Mathf.Sin(u * 13 + v * 8) * Mathf.Cos(v * 11 - u * 4));
                return plaster.Lerp(new Color("827b58"), damp * .42f).Darkened(mottling + .07f * MathF.Pow(v, 5));
            }
            for (int y = 0; y < rows; y++) for (int x = 0; x < columns; x++)
            {
                var a = Point(x, y); var b = Point(x + 1, y); var c = Point(x + 1, y + 1); var d = Point(x, y + 1);
                art.Triangle(a, b, c, Tone(x, y), Tone(x + 1, y), Tone(x + 1, y + 1), Vector3.Back, Vector3.Back, Vector3.Back);
                art.Triangle(a, c, d, Tone(x, y), Tone(x + 1, y + 1), Tone(x, y + 1), Vector3.Back, Vector3.Back, Vector3.Back);
            }
        }
        for (int side = -1; side <= 1; side += 2)
        {
            art.Transform = house * new Transform3D(Basis.FromEuler(new(0, side > 0 ? 0 : Mathf.Pi, 0)), Vector3.Zero);
            WeatheredWall(new(-side * .15f, .59f, .451f), 1.28f, .94f);
            WeatheredWall(new(side * .74f, .52f, .341f), .55f, .80f);
        }
        art.Transform = house * new Transform3D(Basis.FromEuler(new(0, -Mathf.Pi / 2, 0)), new(-.841f, 0, 0));
        WeatheredWall(new(0, .59f, 0), .81f, .94f);
        art.Transform = house * new Transform3D(Basis.FromEuler(new(0, Mathf.Pi / 2, 0)), new(1.061f, 0, 0));
        WeatheredWall(new(0, .52f, 0), .59f, .80f);
        art.Transform = house;

        // Dark inset panels sit behind substantial jambs and a lintel, not on top of them.
        art.RoundedBox(new(-.39f, .435f, .468f), new(.35f, .61f, .028f), .006f, iron);
        for (int i = 0; i < 6; i++)
            art.RoundedBox(new(-.535f + i * .058f, .43f, .487f), new(.053f, .58f, .018f), .003f, new Color("365660").Lightened(i % 2 * .035f));
        for (int side = -1; side <= 1; side += 2)
            art.RoundedBox(new(-.39f + side * .205f, .435f, .495f), new(.07f, .67f, .09f), .008f, cut);
        art.RoundedBox(new(-.39f, .795f, .50f), new(.51f, .085f, .12f), .01f, cut);
        art.Ellipsoid(new(-.28f, .43f, .51f), new(.016f, .018f, .012f), new("c6ab6a"), 6, 4);
        Window(art, new(.22f, .64f, .472f), .20f, .30f, glass, cut);
        Window(art, new(-.15f, 1.295f, .476f), .15f, .23f, glass, cut);
        Window(art, new(.80f, .56f, .356f), .18f, .28f, glass, cut);
        art.Transform = house * new Transform3D(Basis.FromEuler(new(0, Mathf.Pi / 2, 0)), new(1.07f, 0, 0));
        Window(art, new(0, .56f, .01f), .22f, .30f, glass, cut);
        art.Face(new(-.34f, .94f, 0), new(.34f, .94f, 0), new(0, 1.39f, 0), plaster);
        art.RoundedBox(new(0, .94f, .02f), new(.73f, .08f, .07f), .008f, wood);
        art.RoundedBox(new(0, 1.16f, .02f), new(.055f, .42f, .065f), .005f, wood);
        art.Transform = house;

        void TiledRoof(float halfWidth, float halfLength, float peak, float eave, int rows, int columns)
        {
            for (int side = -1; side <= 1; side += 2)
            {
                Vector3 Point(float t, float z, float lift = 0) => new(side * halfWidth * t, Mathf.Lerp(peak, eave, t) + lift, -side * z);
                art.Quad(Point(0, -halfLength), Point(1, -halfLength), Point(1, halfLength), Point(0, halfLength), roof.Darkened(.22f));
                float tileLength = halfLength * 2 / columns;
                for (int row = 0; row < rows; row++) for (int column = 0; column < columns; column++)
                {
                    float a = row / (float)rows, b = (row + 1f) / rows - .009f;
                    float z = -halfLength + column * tileLength;
                    art.Quad(Point(a, z, .008f), Point(b, z, .015f), Point(b, z + tileLength - .007f, .015f), Point(a, z + tileLength - .007f, .008f), roof.Lightened((row + column * 2) % 4 * .018f));
                }
                art.Quad(Point(1, halfLength), Point(1, -halfLength), Point(1, -halfLength, -.035f), Point(1, halfLength, -.035f), roof.Darkened(.20f));
                for (int end = -1; end <= 1; end += 2)
                {
                    var a = Point(0, end * halfLength); var b = Point(1, end * halfLength);
                    if (end > 0) art.Quad(a, b, b - Vector3.Up * .035f, a - Vector3.Up * .035f, roof.Darkened(.10f));
                    else art.Quad(b, a, a - Vector3.Up * .035f, b - Vector3.Up * .035f, roof.Darkened(.10f));
                }
            }
            art.Tube(new(0, peak + .018f, -halfLength - .025f), new(0, peak + .018f, halfLength + .025f), .033f, .033f, roof.Lightened(.12f), 4);
        }
        art.Transform = house * new Transform3D(Basis.Identity, new(-.15f, 0, 0));
        TiledRoof(.83f, .64f, 1.84f, .95f, 2, 5);
        art.Transform = house * new Transform3D(Basis.FromEuler(new(0, Mathf.Pi / 2, 0)), new(.68f, 0, 0));
        TiledRoof(.39f, .46f, 1.40f, .88f, 2, 3);
        art.Transform = house;

        // Open chimney throat with a raised rain cap, held up by two stone cheeks.
        art.RoundedBox(new(-.58f, 1.72f, -.22f), new(.20f, .79f, .22f), .016f, plaster);
        art.RoundedBox(new(-.58f, 2.10f, -.22f), new(.28f, .07f, .30f), .011f, new("d1c7a9"));
        art.RoundedBox(new(-.58f, 2.14f, -.22f), new(.15f, .014f, .16f), .003f, iron);
        for (int side = -1; side <= 1; side += 2)
            art.RoundedBox(new(-.58f + side * .091f, 2.21f, -.22f), new(.045f, .17f, .19f), .006f, plaster);
        art.RoundedBox(new(-.58f, 2.31f, -.22f), new(.29f, .07f, .30f), .011f, plaster);
        for (int i = 0; i < 2; i++)
            art.RoundedBox(new(-.62f + i * .055f, 1.90f - i * .15f, -.104f), new(.028f, .065f, .008f), .003f, new("b5ac91"));

        // A horizontal iron bracket really meets both hanging links; the anchor has a ring and curved flukes.
        art.RoundedBox(new(1.083f, 1.20f, .17f), new(.04f, .22f, .075f), .007f, iron);
        art.Tube(new(1.09f, 1.29f, .17f), new(1.54f, 1.29f, .17f), .019f, .019f, iron, 6);
        art.Tube(new(1.09f, 1.12f, .17f), new(1.33f, 1.29f, .17f), .013f, .013f, iron, 6);
        void Ring(Vector3 center, float radius, float thickness, Color color)
        {
            for (int i = 0; i < 12; i++)
            {
                float a = i * Mathf.Tau / 12, b = (i + 1) * Mathf.Tau / 12;
                art.Tube(center + new Vector3(Mathf.Cos(a), Mathf.Sin(a), 0) * radius,
                    center + new Vector3(Mathf.Cos(b), Mathf.Sin(b), 0) * radius, thickness, thickness, color, 5);
            }
        }
        Ring(new(1.54f, 1.31f, .17f), .041f, .012f, iron);
        for (int side = -1; side <= 1; side += 2)
            art.Tube(new(1.35f + side * .11f, 1.29f, .17f), new(1.35f + side * .11f, 1.18f, .17f), .008f, .008f, iron, 5);
        art.RoundedBox(new(1.35f, .99f, .17f), new(.37f, .43f, .05f), .009f, wood);
        art.RoundedBox(new(1.35f, .99f, .201f), new(.315f, .375f, .015f), .004f, new("304c56"));
        Color ivory = new("eee2b6");
        Ring(new(1.35f, 1.115f, .219f), .024f, .007f, ivory);
        art.Tube(new(1.35f, 1.093f, .219f), new(1.35f, .865f, .219f), .009f, .009f, ivory, 5);
        art.Tube(new(1.28f, 1.055f, .219f), new(1.42f, 1.055f, .219f), .009f, .009f, ivory, 5);
        for (int side = -1; side <= 1; side += 2)
        {
            Vector3[] curve = [new(1.35f, .865f, .219f), new(1.35f + side * .065f, .89f, .219f), new(1.35f + side * .105f, .945f, .219f)];
            for (int i = 0; i < 2; i++) art.Tube(curve[i], curve[i + 1], .009f, .009f, ivory, 5);
            art.Face(curve[2] + new Vector3(-.018f, -.005f, 0), curve[2] + new Vector3(.018f, -.005f, 0), curve[2] + new Vector3(0, .033f, 0), ivory);
        }
        art.RoundedBox(new(-.39f, .085f, .57f), new(.52f, .14f, .24f), .018f, new("929c94"));
        Barrel(art, new(-1.04f, .02f, .28f), .23f);
        Barrel(art, new(.57f, .02f, .65f), .25f);
        Barrel(art, new(.84f, .02f, .72f), .22f);
        Shrub(art, new(-.88f, .02f, .56f), .16f, 41);
        Shrub(art, new(-.02f, .02f, .53f), .14f, 42);
        Shrub(art, new(1.01f, .02f, .44f), .17f, 43);
    }

    private static void Shipwreck(Sculptor art, bool afloat = false)
    {
        Color wood = new("896039"), cut = new("b68a52"), dark = new("564330");
        float[] xs = [-1.22f, -1.10f, -.83f, -.48f, -.10f, .28f, .57f, .86f, 1.12f];
        float[] widths = [.045f, .23f, .40f, .49f, .50f, .46f, .40f, .30f, .12f];
        float[] heights = [1.05f, .96f, .88f, .78f, .72f, .66f, .58f, .39f, .18f];
        Vector3 Hull(int station, float t, int side, bool inside = false) => new(xs[station], .045f + heights[station] * t,
            side * (.045f + (widths[station] - .045f) * MathF.Sqrt(t) - (inside ? .035f : 0)));
        // Thick individual strakes: a high surviving port bow, a torn-away near side,
        // and staggered broken ends expose the ribs and hold instead of a flat plank wall.
        for (int side = -1; side <= 1; side += 2)
        {
            for (int row = 0; row < 6; row++)
            {
                int end = row < 2 ? 8 : side > 0 ? (row == 2 ? 6 : row == 3 ? 4 : row == 4 ? 3 : 2) : 8 - (row % 3);
                for (int station = 0; station < end; station++)
                {
                    float a = row / 6f, b = (row + 1f) / 6 - .012f;
                    void Plank(Vector3 p, Vector3 q, Vector3 r, Vector3 t, Color color)
                    {
                        if (side > 0) art.Quad(p, q, r, t, color); else art.Quad(t, r, q, p, color);
                    }
                    Color timber = row == 0 ? wood.Lerp(new Color("506a5b"), .30f) : wood.Lightened((row + station) % 3 * .035f);
                    Plank(Hull(station, a, side), Hull(station + 1, a, side), Hull(station + 1, b, side), Hull(station, b, side), timber);
                    Plank(Hull(station, b, side, true), Hull(station + 1, b, side, true), Hull(station + 1, a, side, true), Hull(station, a, side, true), cut.Darkened(.13f));
                    Plank(Hull(station, b, side), Hull(station + 1, b, side), Hull(station + 1, b, side, true), Hull(station, b, side, true), cut);
                    if (station == end - 1)
                    {
                        Vector3 tip = (Hull(end, a, side) + Hull(end, b, side)) * .5f + new Vector3(.10f + row % 2 * .05f, .035f, 0);
                        art.Face(Hull(end, a, side), tip, Hull(end, b, side), cut.Darkened(.10f));
                        art.Quad(Hull(end, a, side), Hull(end, b, side), Hull(end, b, side, true), Hull(end, a, side, true), dark);
                    }
                    if (station > 0 && row % 2 == 0)
                        art.Ellipsoid(Hull(station, (a + b) / 2, side) + new Vector3(0, 0, side * .008f), new(.012f, .012f, .007f), dark, 5, 3);
                }
            }
            for (int station = 1; station < 8; station++)
            {
                float rim = side > 0 ? .52f : .94f;
                for (int section = 0; section < 3; section++)
                    art.Tube(Hull(station, section * rim / 3, side, true), Hull(station, (section + 1) * rim / 3, side, true), .033f, .028f, wood.Darkened(.13f), 4);
            }
        }
        for (int i = 0; i < 7; i++)
            art.RoundedBox(new(-.78f + i * .22f, .18f, 0), new(.21f, .06f, .34f + .23f * Mathf.Sin(i * Mathf.Pi / 7)), .007f, cut.Darkened(i % 3 * .035f));
        art.Tube(new(-1.22f, .045f, 0), new(-1.22f, 1.17f, 0), .052f, .031f, cut, 5);
        art.Tube(new(.28f, .10f, -.10f), new(.56f, 1.79f, -.10f), .046f, .033f, wood, 7);
        art.Tube(new(-.09f, 1.52f, -.045f), new(1.19f, 1.65f, -.045f), .034f, .025f, cut, 6);
        for (int i = 0; i < 3; i++)
            art.Tube(new(.47f, 1.48f + i * .04f, -.10f), new(.53f, 1.48f + i * .04f, -.10f), .046f, .046f, dark, 6);
        // Broad folded remnants, with uneven cuts and genuine missing cloth between them.
        for (int panel = 0; panel < 2; panel++)
        {
            float left = panel == 0 ? -.055f : .61f, width = panel == 0 ? .46f : .54f;
            for (int strip = 0; strip < 4; strip++)
            {
                Vector3 Top(float t) => new(left + t * width, 1.53f + (left + t * width) * .10f, -.025f);
                Vector3 Hem(float t) => Top(t) + new Vector3(-.05f * t, -.47f - .11f * Mathf.Sin(t * 13 + panel), .10f + .06f * Mathf.Sin(t * Mathf.Pi));
                float a = strip / 4f, b = (strip + 1) / 4f;
                art.Quad(Top(a), Hem(a), Hem(b), Top(b), new Color("d3c59c").Darkened(strip % 2 * .055f));
            }
        }
        art.Tube(new(-.08f, 1.52f, -.05f), new(-.51f, .38f, -.28f), .009f, .009f, new("ab9466"), 5);
        SupplyCrate(art, new(-.18f, .32f, -.02f), .23f);
        var wreck = art.Transform;
        for (int i = 0; i < 4; i++)
        {
            float height = afloat ? .17f : .055f;
            art.Transform = wreck * new Transform3D(Basis.FromEuler(new(0, -.55f + i * .43f, .04f)), new(.54f + i * .20f, height, .62f + (i % 2) * .13f));
            art.RoundedBox(Vector3.Zero, new(.39f - i * .035f, .045f, .085f), .005f, wood.Lightened(i * .025f));
        }
        art.Transform = wreck;
    }

    private static void SeaCave(Sculptor art, uint seed)
    {
        // An actual recessed shell: the mouth is empty, with side walls, ceiling,
        // a shaded floor and a rear wall well behind the facade.
        Vector2[] outer = [new(-1.08f,.02f),new(-1.10f,.65f),new(-.82f,1.25f),new(-.43f,1.62f),new(.22f,1.55f),new(.72f,1.24f),new(1.04f,.72f),new(1.08f,.02f)];
        Vector2[] inner = [new(-.48f,.02f),new(-.51f,.46f),new(-.34f,.90f),new(-.12f,1.04f),new(.25f,1.00f),new(.46f,.76f),new(.51f,.39f),new(.49f,.02f)];
        Color rock = new("77868a"), recess = new("354d52");
        Vector3 Front(Vector2 p) => new(p.X, p.Y, .38f);
        Vector3 Back(Vector2 p) => new(p.X * .82f, p.Y * .84f, -.82f);
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
            art.Face(new(0, .34f, -.83f), Back(inner[i + 1]), Back(inner[i]), recess.Darkened(.27f));
            art.Quad(Back(outer[i + 1]), Back(inner[i + 1]), Back(inner[i]), Back(outer[i]), rock.Darkened(.12f));
        }
        art.Face(new(0, .34f, -.83f), Back(inner[0]), Back(inner[^1]), recess.Darkened(.27f));
        // Sand at the mouth fades into the recess instead of reading as a flat dark door.
        for (int i = 0; i < 4; i++)
        {
            float a = i / 4f, b = (i + 1) / 4f;
            Vector3 Floor(float side, float t) => new(side * Mathf.Lerp(.49f, .40f, t), .026f, Mathf.Lerp(.46f, -.83f, t));
            Color Tone(float t) => new Color("c2ae7d").Lerp(new Color("304749"), Mathf.SmoothStep(0, .85f, t));
            art.Triangle(Floor(-1, a), Floor(1, a), Floor(1, b), Tone(a), Tone(a), Tone(b), Vector3.Up, Vector3.Up, Vector3.Up);
            art.Triangle(Floor(-1, a), Floor(1, b), Floor(-1, b), Tone(a), Tone(b), Tone(b), Vector3.Up, Vector3.Up, Vector3.Up);
        }
        for (int side = -1; side <= 1; side += 2)
        {
            art.Boulder(new(side * .93f, .20f, .30f), new(.50f, .48f, .54f), rock, seed + (uint)(side + 3));
            HangingMoss(art, new(side * .65f, 1.27f, .43f), .57f, seed + (uint)(side + 8));
        }
        art.Boulder(new(-.72f, .92f, -.40f), new(.69f, .95f, .85f), rock, seed + 15);
        art.Boulder(new(.72f, .72f, -.40f), new(.70f, .92f, .83f), rock, seed + 17);
        art.Boulder(new(-.12f, 1.56f, -.13f), new(.65f, .14f, .44f), Leaf, seed + 19);
        for (int i = 0; i < 4; i++)
            Frond(art, new(-.12f, 1.62f, -.02f), i * 1.7f, .40f, .13f, .10f, Leaf.Lightened(i % 2 * .12f));
        HangingMoss(art, new(-.21f, 1.56f, .37f), .39f, seed + 22);
        Shrub(art, new(-1.0f, .04f, .53f), .18f, seed + 24);
    }

    private static void AncientArch(Sculptor art, uint seed)
    {
        Color stone = new("788781"), pale = new("bab79a");
        var arch = art.Transform;
        for (int side = -1; side <= 1; side += 2)
        {
            art.RoundedBox(new(side * .58f, .07f, 0), new(.52f, .14f, .55f), .04f, stone.Darkened(.13f));
            for (int block = 0; block < 3; block++)
            {
                art.Transform = arch * new Transform3D(Basis.FromEuler(new(0, side * (block - 1) * .018f, side * .008f)), new(side * .58f, .31f + block * .365f, 0));
                art.RoundedBox(Vector3.Zero, new(.43f + block % 2 * .025f, .352f, .46f), .035f, stone.Lightened(block % 2 * .035f));
            }
            art.Transform = arch;
            Glyph(new(side * .58f, .35f, .239f), .11f);
            Glyph(new(side * .58f, .85f, .239f), .11f);
            art.Transform = arch * new Transform3D(Basis.FromEuler(new(0, 0, -side * .36f)), new(side * .45f, 1.33f, 0));
            art.RoundedBox(Vector3.Zero, new(.45f, .40f, .48f), .035f, stone.Lightened(.035f));
            art.Transform = arch;
            HangingMoss(art, new(side * .64f, 1.40f, .22f), side < 0 ? .46f : .29f, seed + (uint)(side + 9));
            art.Boulder(new(side * .88f, .11f, .22f), new(.32f, .28f, .33f), stone, seed + (uint)(side + 2));
        }
        // A broad keystone and angled shoulders match the reference's heavy, flat-topped ruin.
        art.RoundedBox(new(0, 1.52f, 0), new(.64f, .36f, .50f), .04f, stone.Lightened(.055f));
        Glyph(new(0, 1.51f, .258f), .095f);
        art.Boulder(new(-.22f, 1.69f, -.04f), new(.35f, .09f, .32f), Leaf, seed + 21);
        Shrub(art, new(-.87f, .02f, .43f), .15f, seed + 23);
        void Glyph(Vector3 center, float radius)
        {
            Vector2[] spiral = [new(-.8f,-1),new(.85f,-1),new(1,-.7f),new(1,.75f),new(.7f,1),new(-.8f,1),new(-1,.7f),new(-1,-.5f),new(.35f,-.5f),new(.48f,-.3f),new(.48f,.35f),new(-.25f,.35f)];
            for (int i = 0; i < spiral.Length - 1; i++)
            {
                var a = center + new Vector3(spiral[i].X, spiral[i].Y, 0) * radius;
                var b = center + new Vector3(spiral[i + 1].X, spiral[i + 1].Y, 0) * radius;
                art.Tube(a + new Vector3(.004f, -.004f, -.002f), b + new Vector3(.004f, -.004f, -.002f), .012f, .012f, stone.Darkened(.20f), 4);
                art.Tube(a, b, .008f, .008f, pale, 4);
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
