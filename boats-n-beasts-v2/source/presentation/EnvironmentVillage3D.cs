using Godot;
using BoatsNBeasts.Core;

namespace BoatsNBeasts;

public static partial class EnvironmentArt3D
{
    private static void Lighthouse(Sculptor art, uint seed, float spread, float bluff)
    {
        Color coral = new("eb624d"), cream = new("f8e1b0"), frame = new("323848"), rail = new("a96747");
        var origin = art.Transform;
        Vector2[] shoreLedge = [
            new(-1.06f, -.27f), new(-.80f, -.77f), new(-.26f, -.99f), new(.26f, -.91f),
            new(.51f + spread * .18f, -.72f), new(.78f + spread * .40f, -.67f - spread * .12f),
            new(1.05f + spread * .54f, -.32f), new(1.08f + spread * .55f, .16f),
            new(.81f + spread * .54f, .66f), new(.39f + spread * .27f, .85f), new(-.18f, 1.06f),
            new(-.57f, .86f), new(-.99f, .44f)
        ];
        float ledgeHeight = .28f + spread * .075f;
        SandstoneShelf(art, Vector2.Zero, shoreLedge, -.11f, ledgeHeight, seed);
        if (spread > .55f)
        {
            Vector2[] apron = [new(-.40f, -.16f), new(.06f, -.28f), new(.39f, -.14f),
                new(.41f, .15f), new(.11f, .33f), new(-.26f, .32f), new(-.42f, .11f)];
            SandstoneShelf(art, new(-.28f, .98f), apron, -.11f, .19f + spread * .025f, seed + 30);
        }
        if (bluff > .48f) LighthouseBluff(art, bluff, seed);

        var terrace = new Vector2(-.04f - spread * .22f, -.10f - spread * .15f);
        float terraceHeight = .55f + spread * .09f;
        Vector2 terraceSize = new(1 + spread * .15f, 1 + spread * .08f);
        Vector2[] upperLedge = [
            new(-.89f, -.28f), new(-.63f, -.70f), new(-.17f, -.86f), new(.45f, -.75f), new(.79f, -.46f),
            new(.93f, .10f), new(.71f, .58f), new(.29f, .78f), new(-.25f, .88f), new(-.69f, .65f), new(-.88f, .24f)
        ];
        for (int i = 0; i < upperLedge.Length; i++) upperLedge[i] *= terraceSize;
        SandstoneShelf(art, terrace, upperLedge, -.11f, terraceHeight, seed + 17);

        Shrub(art, new(-.29f, ledgeHeight - .02f, .79f), .20f, seed + 65);
        if (spread > .52f)
        {
            Shrub(art, new(1.06f * spread + .20f, ledgeHeight - .02f, .22f), .24f, seed + 24);
            Shrub(art, new(.88f * spread + .20f, ledgeHeight - .02f, -.34f), .15f, seed + 61);
        }

        float widthScale = 1 + spread * .18f;
        art.Transform *= new Transform3D(Basis.Identity.Scaled(new(widthScale, 1, widthScale)), new(terrace.X, terraceHeight - .005f, terrace.Y));
        Vector3 RingPoint(int side, float y, float radius)
        {
            float angle = (side + .5f) * Mathf.Tau / 8;
            return new(Mathf.Cos(angle) * radius, y, Mathf.Sin(angle) * radius);
        }
        void Band(float y0, float y1, float bottom, float top, Color color, bool cap = false)
        {
            for (int i = 0; i < 8; i++)
            {
                var a = RingPoint(i, y1, top);
                var b = RingPoint(i + 1, y1, top);
                art.Quad(RingPoint(i + 1, y0, bottom), RingPoint(i, y0, bottom), a, b, color);
                if (cap) art.Face(new(0, y1, 0), b, a, color);
            }
        }

        Band(0, .15f, .66f, .66f, coral, true);
        Band(.15f, .50f, .60f, .55f, cream);
        Band(.50f, .93f, .55f, .48f, coral);
        Band(.93f, 1.30f, .48f, .42f, cream);
        Band(1.30f, 1.53f, .42f, .38f, coral);
        Band(1.53f, 1.61f, .39f, .58f, rail);
        Band(1.61f, 1.68f, .58f, .58f, cream, true);
        Band(1.68f, 1.73f, .39f, .39f, frame);

        for (int i = 0; i < 8; i++)
        {
            var a = RingPoint(i, 1.73f, .38f);
            var b = RingPoint(i + 1, 1.73f, .38f);
            var rise = Vector3.Up * .41f;
            var normal = (a - b).Cross(rise).Normalized();
            Color glass = new Color("a4dfd5").Lerp(new Color("75bcbc"), i % 3 * .28f);
            art.Triangle(b, a, a + rise, glass, glass, glass, normal, normal, normal, "lantern");
            art.Triangle(b, a + rise, b + rise, glass, glass, glass, normal, normal, normal, "lantern");
            art.Tube(a, a + rise, .020f, .020f, frame, 5);

            var post = RingPoint(i, 1.67f, .55f);
            var railHeight = Vector3.Up * .14f;
            art.Tube(post, post + railHeight, .023f, .023f, rail, 4);
            art.Tube(post + railHeight, RingPoint(i + 1, 1.81f, .55f), .023f, .023f, rail, 4);
        }

        Band(2.14f, 2.22f, .45f, .49f, coral.Darkened(.15f));
        Band(2.22f, 2.48f, .49f, .16f, coral, true);
        Band(2.48f, 2.56f, .13f, .10f, rail, true);
        art.Tube(new(0, 2.54f, 0), new(0, 3.19f, 0), .018f, .018f, rail, 5);
        art.Tube(new(0, 3.18f, 0), new(0, 3.22f, 0), .028f, .028f, cream, 5);
        art.Quad(new(0, 3.16f, 0), new(.21f, 3.19f, .04f), new(.19f, 3.01f, .04f), new(0, 2.99f, 0), coral);
        art.Quad(new(.21f, 3.19f, .04f), new(.40f, 3.14f, -.02f), new(.38f, 3.00f, -.02f), new(.19f, 3.01f, .04f), coral.Lightened(.05f));
        art.Face(new(.40f, 3.14f, -.02f), new(.56f, 3.17f, 0), new(.38f, 3.00f, -.02f), coral);

        var tower = art.Transform;
        Opening(0, .155f, .560f, .16f, .22f);
        Opening(Mathf.Pi / 4, .975f, .444f, .12f, .17f);
        art.Transform = origin;

        void Opening(float yaw, float baseHeight, float depth, float width, float height)
        {
            art.Transform = tower * new Transform3D(Basis.FromEuler(new(0, yaw, 0)), Vector3.Zero);
            Vector3 Point(float x, float y) => new(x, baseHeight + y, depth - y * .125f);
            float radius = width * .5f, spring = height - radius;
            art.Quad(Point(-radius, 0), Point(radius, 0), Point(radius, spring), Point(-radius, spring), frame);
            for (int i = 0; i < 5; i++)
            {
                Vector3 Arc(int j) => Point(radius * Mathf.Cos(j * Mathf.Pi / 5), spring + radius * Mathf.Sin(j * Mathf.Pi / 5));
                art.Face(Point(0, spring), Arc(i), Arc(i + 1), frame);
            }
        }
    }

    private static void LighthouseBluff(Sculptor art, float reach, uint seed)
    {
        var crest = new Vector2(.96f + .34f * reach, -.48f - .28f * reach);
        float height = .37f + .065f * reach;
        Vector2[] shoulder = [
            new(-.66f, -.18f), new(-.47f, -.57f), new(.04f, -.65f), new(.48f, -.55f), new(.70f, -.39f),
            new(.88f, -.13f), new(.74f, .16f), new(.47f, .27f), new(.19f, .44f), new(-.18f, .34f), new(-.56f, .45f)
        ];
        for (int i = 0; i < shoulder.Length; i++) shoulder[i] *= .68f + .32f * reach;
        SandstoneShelf(art, crest, shoulder, -.11f, height, seed + 26);
        Palm(art, new(crest.X + .30f, height - .015f, crest.Y - .10f), 1.19f, seed + 53);
        Shrub(art, new(crest.X + .46f, height - .025f, crest.Y - .06f), .20f, seed + 103);
        Pennants(art, new(crest.X + .13f, height - .013f, crest.Y + .19f), .65f, -.25f);
    }

    private static void SandstoneShelf(Sculptor art, Vector2 center, Vector2[] rim, float bottom, float top, uint seed)
    {
        var rng = new SeedRandom(seed ^ 0x67b3u);
        for (int i = 0; i < rim.Length; i++) rim[i] *= rng.Range(.96f, 1f);

        Color face = new("e5a27a"), cap = new("f8d69d");
        Vector3 Point(int side, float y, float scale)
        {
            var p = center + rim[side % rim.Length] * scale;
            return new(p.X, y, p.Y);
        }
        for (int i = 0; i < rim.Length; i++)
        {
            var a = Point(i, top, .95f);
            var b = Point(i + 1, top, .95f);
            art.Quad(Point(i + 1, bottom, 1), Point(i, bottom, 1), a, b, face.Lightened(i % 3 * .035f));
            art.Face(new(center.X, top, center.Y), b, a, cap);
        }
    }

    private static void MarketStall(Sculptor art)
    {
        Color wood = new("85613c"), edge = new("af8953"), canvas = new("d6c9a2"), teal = new("497780");
        for (int x = -1; x <= 1; x += 2) for (int z = -1; z <= 1; z += 2)
        {
            art.RoundedBox(new(x * .64f, z < 0 ? .80f : .69f, z * .37f), new(.075f, z < 0 ? 1.60f : 1.38f, .075f), .009f, wood);
            art.RoundedBox(new(x * .64f, .07f, z * .37f), new(.10f, .14f, .10f), .012f, wood.Darkened(.15f));
        }
        for (int side = -1; side <= 1; side += 2)
        {
            art.Tube(new(-.72f, side < 0 ? 1.58f : 1.36f, side * .41f), new(.72f, side < 0 ? 1.58f : 1.36f, side * .41f), .036f, .036f, edge, 5);
            art.Tube(new(side * .64f, 1.59f, -.43f), new(side * .64f, 1.35f, .43f), .028f, .028f, wood, 5);
        }
        // Broad stripes follow a sloping canvas awning; each has a rounded hanging hem.
        const float stripeWidth = 1.36f / 6;
        for (int stripe = 0; stripe < 6; stripe++)
        {
            float x = -.68f + stripe * stripeWidth;
            Color cloth = stripe % 2 == 0 ? teal : canvas;
            Vector3 P(float xx, float t) => new(xx, 1.59f - .25f * t - .025f * Mathf.Sin(t * Mathf.Pi), -.47f + t * 1.0f);
            for (int j = 0; j < 6; j++)
            {
                float a = j / 6f, b = (j + 1) / 6f;
                art.Quad(P(x, b), P(x + stripeWidth, b), P(x + stripeWidth, a), P(x, a), cloth);
            }
            for (int j = 0; j < 4; j++)
            {
                float a = j / 4f, b = (j + 1) / 4f;
                Vector3 Hem(float t) => new(x + t * stripeWidth, 1.19f - .04f * Mathf.Sin(t * Mathf.Pi), .535f);
                art.Quad(new(x + a * stripeWidth, 1.34f, .53f), Hem(a), Hem(b), new(x + b * stripeWidth, 1.34f, .53f), cloth.Darkened(.05f));
            }
        }
        for (int i = 0; i < 7; i++)
            art.RoundedBox(new(0, .59f, -.25f + i * .135f), new(1.40f, .065f, .129f), .008f, edge.Darkened(i % 2 * .06f));
        art.RoundedBox(new(0, .46f, .60f), new(1.38f, .21f, .055f), .008f, wood);
        // Produce trays, bottles and spare crates make the stall read as a shop.
        for (int side = -1; side <= 1; side += 2)
        {
            if (side < 0) art.RoundedBox(new(side * .40f, .64f, .43f), new(.37f, .08f, .30f), .009f, wood);
            else art.Tube(new(.40f, .62f, .43f), new(.40f, .72f, .43f), .12f, .19f, canvas, 10);
            for (int i = 0; i < 6; i++)
                art.Ellipsoid(new(side * .40f + (i % 3 - 1) * .09f, side < 0 ? .73f : .76f, .345f + i / 3 * .10f), new(.057f, .056f, .053f), side < 0 ? new("c39545") : new("86a54c"), 7, 4);
        }
        for (int i = 0; i < 3; i++)
        {
            float x = -.13f + i * .13f;
            art.Tube(new(x, .63f, .22f), new(x, .83f, .22f), .043f, .033f, new("629092"), 8);
            art.Tube(new(x, .83f, .22f), new(x, .91f, .22f), .018f, .018f, new("629092"), 6);
        }
        SupplyCrate(art, new(-.44f, .14f, .57f), .25f);
        SupplyCrate(art, new(-.32f, .14f, -.52f), .27f);
        Barrel(art, new(.84f, .02f, -.15f), .23f);
    }

    private static void SupplyCrate(Sculptor art, Vector3 at, float size)
    {
        Color wood = new("89643d"), trim = new("b08752");
        art.RoundedBox(at, new(size, size, size), .008f, wood);
        for (int side = -1; side <= 1; side += 2)
        {
            art.RoundedBox(at + new Vector3(0, side * size * .35f, size * .51f), new(size * .98f, size * .12f, .025f), .003f, trim);
            art.RoundedBox(at + new Vector3(side * size * .35f, 0, size * .51f), new(size * .12f, size, .025f), .003f, trim);
        }
        art.Tube(at + new Vector3(-size * .38f, -size * .35f, size * .52f), at + new Vector3(size * .38f, size * .35f, size * .52f), .016f, .016f, trim, 4);
    }

    private static void Windmill(Sculptor art)
    {
        Color plaster = new("c5b790"), wood = new("795536"), cut = new("ad8150"), cloth = new("dfd3ad");
        art.Tube(new(0, 0, 0), new(0, .13f, 0), .47f, .44f, new("9f9e88"), 8);
        art.Tube(new(0, .10f, 0), new(0, 1.57f, 0), .41f, .27f, plaster, 8);
        art.Tube(new(0, 1.54f, 0), new(0, 2.05f, 0), .43f, .018f, new("c87d39"), 8);
        art.Tube(new(0, 1.54f, 0), new(0, 1.59f, 0), .43f, .42f, wood, 8);
        art.RoundedBox(new(0, .29f, .392f), new(.17f, .32f, .036f), .009f, cut);
        art.RoundedBox(new(0, .29f, .414f), new(.12f, .27f, .016f), .004f, new("3d5960"));
        Window(art, new(0, .81f, .347f), .085f, .17f, new("35545b"), new("aaa486"));
        var mill = art.Transform;
        // Four framed canvas vanes, attached to a single visible axle.
        art.Tube(new(0, 1.58f, .21f), new(0, 1.58f, .58f), .09f, .09f, wood, 8);
        for (int blade = 0; blade < 4; blade++)
        {
            art.Transform = mill * new Transform3D(Basis.FromEuler(new(0, 0, Mathf.Pi / 4 + blade * Mathf.Pi / 2)), new(0, 1.58f, .59f));
            art.RoundedBox(new(0, .71f, 0), new(.047f, 1.32f, .045f), .006f, wood);
            art.RoundedBox(new(.36f, .94f, 0), new(.04f, .81f, .045f), .006f, wood);
            for (int panel = 0; panel < 2; panel++)
            {
                float y = .55f + panel * .39f;
                art.Quad(new(.025f, y, .02f), new(.34f, y, .02f), new(.34f, y + .38f, .04f), new(.025f, y + .38f, .04f), cloth.Darkened(panel % 2 * .035f));
                art.RoundedBox(new(.18f, y, .04f), new(.43f, .026f, .035f), .004f, cut);
            }
            art.RoundedBox(new(.18f, 1.33f, .025f), new(.43f, .04f, .055f), .005f, cut);
        }
        art.Transform = mill;
        art.Tube(new(0, 1.58f, .60f), new(0, 1.58f, .69f), .14f, .12f, new("4e5450"), 10);
        art.Ellipsoid(new(0, 1.58f, .70f), new(.055f, .055f, .025f), cut, 8, 4);
        art.Boulder(new(-.43f, .08f, .25f), new(.30f, .30f, .32f), Stone, 37);
        Shrub(art, new(.39f, .02f, .17f), .17f, 36);
    }
}
