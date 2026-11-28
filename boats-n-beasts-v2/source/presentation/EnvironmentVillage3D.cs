using Godot;
using BoatsNBeasts.Core;

namespace BoatsNBeasts;

public static partial class EnvironmentArt3D
{
    private static Vector2 LighthouseBase(float spread) => new(-.04f - spread * .22f, -.10f - spread * .15f);
    private static float LighthouseBaseHeight(float spread) => .55f + spread * .09f;

    private static void Lighthouse(Sculptor art, float spread)
    {
        Color coral = new("ec634e"), cream = new("f8e1b0"), frame = new("283d4a");
        Color wood = new("87523f"), brass = new("c58455"), roof = new("f56e52");
        var origin = art.Transform;
        var terrace = LighthouseBase(spread);
        float widthScale = 1 + spread * .18f;
        art.Transform *= new Transform3D(Basis.Identity.Scaled(new(widthScale, 1, widthScale)),
            new(terrace.X, LighthouseBaseHeight(spread) - .005f, terrace.Y));
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

        Band(0, .15f, .69f, .69f, coral, true);
        Band(.15f, .50f, .60f, .55f, cream);
        Band(.50f, .93f, .55f, .48f, coral);
        Band(.93f, 1.30f, .48f, .42f, cream);
        Band(1.30f, 1.48f, .42f, .38f, coral);
        Band(1.48f, 1.57f, .39f, .51f, wood);
        Band(1.57f, 1.63f, .51f, .55f, brass);
        Band(1.63f, 1.67f, .55f, .55f, cream, true);
        Band(1.67f, 1.73f, .37f, .37f, brass);
        Band(1.73f, 1.76f, .354f, .354f, frame);

        for (int i = 0; i < 8; i++)
        {
            var a = RingPoint(i, 1.75f, .341f);
            var b = RingPoint(i + 1, 1.75f, .341f);
            var rise = Vector3.Up * .38f;
            var normal = (a - b).Cross(rise).Normalized();
            Color glass = new Color("b7ecdc").Lerp(new Color("79c1be"), i % 3 * .29f);
            art.Triangle(b, a, a + rise, glass, glass, glass, normal, normal, normal, "lantern");
            art.Triangle(b, a + rise, b + rise, glass, glass, glass, normal, normal, normal, "lantern");
            art.Tube(a, a + rise, .023f, .023f, frame, 5);

            var post = RingPoint(i, 1.66f, .505f);
            var next = RingPoint(i + 1, 1.66f, .505f);
            var railHeight = Vector3.Up * .19f;
            var upright = (post + next) * .5f;
            art.Tube(post, post + railHeight, .027f, .025f, wood, 4);
            art.Tube(upright, upright + railHeight, .018f, .018f, wood, 4);
            art.Tube(post + railHeight, next + railHeight, .026f, .026f, brass, 4);
            art.Tube(post + Vector3.Up * .066f, next + Vector3.Up * .066f, .013f, .013f, wood, 4);
        }
        Band(2.10f, 2.15f, .37f, .37f, frame);
        Band(2.15f, 2.20f, .385f, .437f, roof.Darkened(.31f));
        Band(2.20f, 2.245f, .437f, .448f, roof.Darkened(.11f));
        Band(2.245f, 2.56f, .448f, .125f, roof, true);
        Band(2.56f, 2.64f, .125f, .094f, brass, true);
        art.Tube(new(0, 2.62f, 0), new(0, 3.19f, 0), .018f, .018f, wood, 5);
        art.Tube(new(0, 3.18f, 0), new(0, 3.22f, 0), .028f, .028f, cream, 5);
        art.Quad(new(0, 3.16f, 0), new(.20f, 3.19f, .055f), new(.18f, 2.98f, .055f), new(0, 2.96f, 0), coral);
        art.Quad(new(.20f, 3.19f, .055f), new(.38f, 3.12f, -.028f), new(.36f, 2.99f, -.028f), new(.18f, 2.98f, .055f), coral.Lightened(.08f));
        art.Face(new(.38f, 3.12f, -.028f), new(.59f, 3.16f, 0), new(.36f, 2.99f, -.028f), coral);

        var tower = art.Transform;
        Opening(0, .155f, .560f, .135f, .28f);
        Opening(Mathf.Pi / 4, .975f, .444f, .095f, .19f);
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

    private static bool LighthouseHeadland(Sculptor art, uint seed, float spread)
    {
        Vector2[] lowerRim = [
            new(-1.05f, -.27f), new(-.78f, -.68f), new(-.27f, -.96f), new(.29f, -.90f),
            new(.68f, -.70f), new(1.02f, -.39f), new(1.08f, .18f), new(.87f, .44f),
            new(.80f, .70f), new(.37f, .90f), new(-.13f, 1.06f), new(-.53f, .93f),
            new(-.64f, .72f), new(-.96f, .52f), new(-1.10f, .18f)
        ];
        Vector2[] extensions = [
            new(-.19f, -.15f), new(-.03f, -.20f), new(.18f, -.18f), new(.10f, -.26f),
            new(.68f, -.36f), new(.80f, -.21f), new(1.15f, .10f), new(.84f, .16f),
            new(.74f, .32f), new(.37f, .32f), new(.10f, .43f), new(-.20f, .39f),
            new(-.28f, .05f), new(-.36f, .11f), new(-.28f, -.02f)
        ];
        float extension = 0;
        for (float trial = spread; trial > .1f; trial -= .20f)
        {
            var widerRim = lowerRim.Select((point, i) => point + extensions[i] * trial).ToArray();
            if (!FitsShelf(art, Vector2.Zero, widerRim)) continue;
            lowerRim = widerRim;
            extension = trial;
            break;
        }
        float ledgeHeight = .28f + extension * .065f;
        var lower = SandstoneShelf(art, Vector2.Zero, lowerRim, -.13f, ledgeHeight, seed);

        var terrace = LighthouseBase(spread);
        Vector2[] upperRim = [
            new(-.82f, -.36f), new(-.56f, -.69f), new(-.13f, -.87f), new(.39f, -.73f),
            new(.74f, -.49f), new(.86f, -.15f), new(.81f, .30f), new(.59f, .60f),
            new(.20f, .74f), new(-.38f, .82f), new(-.67f, .62f), new(-.91f, .20f)
        ];
        for (int i = 0; i < upperRim.Length; i++) upperRim[i] *= 1 + spread * .16f;
        if (!FitsShelf(art, terrace, upperRim))
            for (int i = 0; i < upperRim.Length; i++) upperRim[i] *= .94f;
        SandstoneShelf(art, terrace, upperRim, -.13f, LighthouseBaseHeight(spread), seed + 17);

        Shrub(art, ShelfPlant(lower, new(-.38f, .73f), .15f), .22f, seed + 65);
        if (extension > .4f)
        {
            Shrub(art, ShelfPlant(lower, new(.96f, .64f), .17f), .25f, seed + 24);
            Shrub(art, ShelfPlant(lower, new(1.12f, .66f), .10f), .14f, seed + 61);
            Shrub(art, ShelfPlant(lower, new(-.53f, .96f), .09f), .13f, seed + 74);
            var spur = new Vector2(-.44f, .92f + extension * .36f);
            Vector2[] toe = [new(-.36f, -.12f), new(-.14f, -.25f), new(.26f, -.23f),
                new(.39f, .04f), new(.18f, .28f), new(-.18f, .26f), new(-.34f, .11f)];
            if (FitsShelf(art, spur, toe))
                SandstoneShelf(art, spur, toe, -.13f, .15f, seed + 30);
        }

        var shoulder = new Vector2(.99f, -.76f);
        Vector2[] shoulderRim = [
            new(-.67f, -.28f), new(-.35f, -.66f), new(.06f, -.74f), new(.42f, -.64f),
            new(.81f, -.53f), new(.75f, -.27f), new(.59f, .06f), new(.43f, .28f),
            new(.23f, .49f), new(-.07f, .35f), new(-.41f, .43f), new(-.68f, .16f)
        ];
        if (extension < .4f || !FitsShelf(art, shoulder, shoulderRim)) return false;

        var raised = SandstoneShelf(art, shoulder, shoulderRim, -.13f, .49f, seed + 26);
        Palm(art, ShelfPlant(raised, new(1.36f, -.93f), .09f), 1.33f, seed + 53);
        Shrub(art, ShelfPlant(raised, new(1.48f, -.77f), .16f), .23f, seed + 103);
        Shrub(art, ShelfPlant(raised, new(1.56f, -.91f), .09f), .13f, seed + 134);
        Pennants(art, ShelfPlant(raised, new(1.15f, -.67f), .29f), .54f, -.25f);
        return true;
    }

    private static Vector3 ShelfPlant((Vector3 Center, Vector2[] Outline) shelf, Vector2 preferred, float radius)
    {
        var (center, outline) = shelf;
        var origin = new Vector2(center.X, center.Z);
        for (int step = 0; step < 8; step++)
        {
            var point = preferred.Lerp(origin, step / 8f);
            if (!Geometry2D.IsPointInPolygon(point, outline)) continue;
            bool supported = true;
            for (int i = 0; i < outline.Length; i++)
            {
                var edge = Geometry2D.GetClosestPointToSegment(point, outline[i], outline[(i + 1) % outline.Length]);
                if (point.DistanceSquaredTo(edge) >= radius * radius) continue;
                supported = false;
                break;
            }
            if (supported) return new(point.X, center.Y - .026f, point.Y);
        }
        return center - Vector3.Up * .026f;
    }

    private static bool FitsShelf(Sculptor art, Vector2 center, Vector2[] rim)
    {
        var outline = rim.Select(point =>
        {
            var world = art.Transform * new Vector3(center.X + point.X, 0, center.Y + point.Y);
            return new Vector2(world.X, world.Z);
        }).ToArray();
        Vector2? chest = art.TreasureSpace is { } treasure ? new Vector2(treasure.X, treasure.Y) : null;
        var jetty = art.JettySpace;
        if (chest is { } chestPoint && Geometry2D.IsPointInPolygon(chestPoint, outline) ||
            jetty is { } pier && (Geometry2D.IsPointInPolygon(pier.Start, outline) || Geometry2D.IsPointInPolygon(pier.End, outline)))
            return false;
        float beach = MathF.Max(.13f, art.BeachReserve);
        for (int i = 0; i < outline.Length; i++)
        {
            var start = outline[i];
            var end = outline[(i + 1) % outline.Length];
            int slices = Math.Max(1, (int)MathF.Ceiling(start.DistanceTo(end) / .14f));
            for (int j = 0; j < slices; j++)
            {
                var point = start.Lerp(end, j / (float)slices);
                if (InlandClearance(art.Footprint!, point) < beach ||
                    chest is { } reserved && point.DistanceTo(reserved) < .55f ||
                    jetty is { } dock && point.DistanceTo(Geometry2D.GetClosestPointToSegment(point, dock.Start, dock.End)) < dock.Width + .10f)
                    return false;
            }
        }
        return true;
    }

    private static (Vector3 Center, Vector2[] Outline) SandstoneShelf(Sculptor art, Vector2 center, Vector2[] rim, float bottom, float top, uint seed)
    {
        var rng = new SeedRandom(seed ^ 0x67b3u);
        var foot = new Vector3[rim.Length];
        var crest = new Vector3[rim.Length];
        var outline = new Vector2[rim.Length];
        var capCenter = new Vector3(center.X, top, center.Y);
        for (int i = 0; i < rim.Length; i++)
        {
            var basePoint = center + rim[i] * rng.Range(.94f, 1);
            var topPoint = center + rim[i] * rng.Range(.84f, .96f);
            foot[i] = new(basePoint.X, bottom, basePoint.Y);
            crest[i] = new(topPoint.X, top + rng.Range(-.020f, .012f), topPoint.Y);
            outline[i] = topPoint;
        }

        Color face = new("dd986f"), cap = new("f6d49b");
        for (int i = 0; i < rim.Length; i++)
        {
            int next = (i + 1) % rim.Length;
            var tone = face.Lerp(cap, rng.Range(0, .22f)).Darkened(rng.Range(0, .065f));
            art.Face(foot[next], foot[i], crest[i], tone);
            art.Face(foot[next], crest[i], crest[next], i % 4 == 1 ? tone.Lightened(.10f) : tone);
            art.Face(capCenter, crest[next], crest[i], cap);
        }
        return (capCenter, outline);
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
