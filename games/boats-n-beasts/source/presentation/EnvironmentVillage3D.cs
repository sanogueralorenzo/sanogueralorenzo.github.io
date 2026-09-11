using Godot;

namespace BoatsNBeasts;

public static partial class EnvironmentArt3D
{
    private static void Lighthouse(Sculptor art)
    {
        Color plaster = new("c9bd97"), band = new("405766"), stone = new("a4a58f"), roof = new("c5813e"), iron = new("596057");
        art.Tube(new(0, 0, 0), new(0, .15f, 0), .48f, .46f, stone, 8);
        art.Tube(new(0, .14f, 0), new(0, 1.67f, 0), .39f, .27f, plaster, 8);
        art.Tube(new(0, .64f, 0), new(0, .98f, 0), .355f, .328f, band, 8);
        foreach (float y in new[] { .20f, .61f, 1.62f })
        {
            float radius = Mathf.Lerp(.39f, .27f, (y - .14f) / 1.53f) + .025f;
            art.Tube(new(0, y, 0), new(0, y + .055f, 0), radius, radius, stone, 8);
        }
        art.RoundedBox(new(0, .30f, .381f), new(.16f, .29f, .035f), .012f, new("796448"));
        art.RoundedBox(new(0, .29f, .402f), new(.11f, .24f, .018f), .005f, band.Darkened(.30f));
        art.RoundedBox(new(0, 1.28f, .308f), new(.08f, .20f, .025f), .008f, stone);
        art.RoundedBox(new(0, 1.28f, .325f), new(.04f, .145f, .012f), .003f, band.Darkened(.30f));
        art.RoundedBox(new(0, .065f, .48f), new(.30f, .13f, .27f), .02f, stone);
        // An octagonal lantern: warm panes inset behind eight iron mullions.
        art.Tube(new(0, 1.68f, 0), new(0, 1.78f, 0), .38f, .38f, stone, 8);
        art.Tube(new(0, 1.74f, 0), new(0, 1.82f, 0), .40f, .36f, plaster, 8);
        art.Tube(new(0, 1.78f, 0), new(0, 1.83f, 0), .33f, .33f, iron, 8);
        for (int i = 0; i < 8; i++)
        {
            float a = i * Mathf.Tau / 8, b = (i + 1) * Mathf.Tau / 8;
            Vector3 P(float angle, float height, float radius) => new(Mathf.Cos(angle) * radius, height, Mathf.Sin(angle) * radius);
            var v0 = P(b, 1.84f, .295f); var v1 = P(a, 1.84f, .295f); var v2 = P(a, 2.28f, .295f); var v3 = P(b, 2.28f, .295f);
            var normal = (v1 - v0).Cross(v2 - v0).Normalized();
            Color amber = new Color("ffd181").Lightened(i % 2 * .10f);
            art.Triangle(v0, v1, v2, amber, amber, amber, normal, normal, normal, "lantern");
            art.Triangle(v0, v2, v3, amber, amber, amber, normal, normal, normal, "lantern");
            art.Tube(P(a, 1.79f, .32f), P(a, 2.32f, .32f), .023f, .023f, iron, 5);
        }
        art.Tube(new(0, 2.28f, 0), new(0, 2.33f, 0), .35f, .35f, roof.Darkened(.22f), 8);
        art.Tube(new(0, 2.33f, 0), new(0, 2.87f, 0), .43f, .02f, roof, 8);
        art.Ellipsoid(new(0, 2.89f, 0), new(.065f, .095f, .065f), roof.Lightened(.12f), 6, 4);
        for (int i = 0; i < 5; i++)
        {
            float a = 1.1f + i * 1.05f;
            art.Boulder(new(Mathf.Cos(a) * .49f, .08f, Mathf.Sin(a) * .49f), new(.23f, .25f, .25f), Stone, (uint)(51 + i));
        }
        Shrub(art, new(-.39f, .03f, .36f), .16f, 51);
        Shrub(art, new(.43f, .03f, .22f), .12f, 54);
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
