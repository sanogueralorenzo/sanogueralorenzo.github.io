using Godot;
using BoatsNBeasts.Core;

namespace BoatsNBeasts;

/// <summary>Seeded, matte miniature scenery. One world unit is 100 simulation units.</summary>
public static class EnvironmentArt3D
{
    private static readonly Color Sand = new("d6bd86"), Stone = new("898b7e"), Leaf = new("647c43");
    private static readonly Dictionary<string, Material> Materials = new();

    public static Node3D Build(Place place)
    {
        var art = new Sculptor();
        var rng = new SeedRandom(place.Style);
        float r = place.Radius * .01f;
        if (place.Kind == PlaceKind.Rock)
        {
            Land(art, r * .88f, place.Style, true);
            Rock(art, new(0, .04f, 0), new(r * 1.7f, r * 1.65f, r * 1.5f), place.Style);
            Rock(art, new(-r * .48f, .01f, r * .5f), new(r * .8f, r * .65f, r * .7f), place.Style + 21);
        }
        else if (place.Kind is PlaceKind.Harbor or PlaceKind.Island)
        {
            Land(art, r, place.Style, false);
            CoveBoulders(art, r, place.Style, place.Kind == PlaceKind.Harbor);
            if (place.Kind == PlaceKind.Harbor)
            {
                AddCottage(art, new(-r * .17f, .15f, -r * .10f), r * .76f, -.20f);
                Dock(art, r);
                Palm(art, new(-r * .60f, .17f, -r * .16f), r * .68f, place.Style);
                Palm(art, new(r * .38f, .18f, -r * .48f), r * .76f, place.Style + 33);
                Rock(art, new(-r * .53f, .09f, r * .53f), new(r * .47f, r * .31f, r * .39f), place.Style + 2);
                Rock(art, new(r * .38f, .12f, -r * .34f), new(r * .56f, r * .76f, r * .54f), place.Style + 9);
                Barrel(art, new(r * .35f, .18f, r * .32f), r * .16f);
                Barrel(art, new(r * .55f, .16f, r * .25f), r * .13f);
            }
            else
            {
                // Off-centre, overlapping shoulders form a cliff silhouette, not a symmetric stack.
                Rock(art, new(-r * .13f, .14f, -r * .22f), new(r * .83f, r * 1.28f, r * .70f), place.Style);
                Rock(art, new(r * .20f, .13f, -r * .04f), new(r * .70f, r * .91f, r * .67f), place.Style + 13);
                Rock(art, new(-r * .36f, .12f, r * .06f), new(r * .52f, r * .57f, r * .63f), place.Style + 31);
                Palm(art, new(r * .51f, .14f, r * .0f), r * .84f, place.Style + 1);
                Palm(art, new(-r * .12f, .17f, r * .46f), r * .64f, place.Style + 2);
                Rock(art, new(r * .52f, .08f, r * .52f), new(r * .38f, r * .25f, r * .31f), place.Style + 3);
            }
            for (int i = 0; i < 13; i++)
            {
                float angle = rng.Range(0, Mathf.Tau), reach = rng.Range(.38f, .73f) * r;
                var at = new Vector3(Mathf.Cos(angle) * reach, .13f, Mathf.Sin(angle) * reach);
                if (place.Kind == PlaceKind.Harbor && at.Z > -.05f && at.X > -.4f * r) continue;
                Shrub(art, at, rng.Range(.15f, .24f) * r, rng.Next());
            }
            for (int i = 0; i < 10; i++)
            {
                float angle = rng.Range(0, Mathf.Tau), reach = rng.Range(.72f, .98f) * r;
                float s = rng.Range(.018f, .052f) * r;
                art.Ellipsoid(new(Mathf.Cos(angle) * reach, .09f, Mathf.Sin(angle) * reach), new(s, s * .7f, s * .9f), Stone.Lightened(.08f), 7, 4);
            }
            for (int i = 0; i < 110; i++)
            {
                float angle = rng.Range(0, Mathf.Tau), reach = rng.Range(.45f, .98f) * r;
                float y = reach < .63f * r ? .182f : Mathf.Lerp(.172f, .08f, (reach / r - .63f) / .35f);
                float s = rng.Range(.003f, .009f) * r;
                art.Ellipsoid(new(Mathf.Cos(angle) * reach, y, Mathf.Sin(angle) * reach), new(s, s * .35f, s * .6f), Sand.Darkened(rng.Range(.08f, .20f)), 5, 3);
            }
        }
        return art.Finish("Environment_" + place.Kind);
    }

    /// <summary>A unit-scale cottage rooted at its floor, for the native style sample.</summary>
    public static Node3D Cottage()
    {
        var art = new Sculptor();
        AddCottage(art, Vector3.Zero, 1, -.20f);
        return art.Finish("Cottage");
    }

    private static float Coast(float a, uint seed) => 1 + .055f * Mathf.Sin(a * 3 + seed % 17) + .040f * Mathf.Cos(a * 5 + seed % 11) + .024f * Mathf.Sin(a * 7 + seed % 23);

    private static float CoveExtension(float angle, uint seed)
    {
        float broad = Mathf.Pow(Mathf.Max(0, Mathf.Sin(angle * 2 + seed % 17)), 2);
        float secondary = Mathf.Pow(Mathf.Max(0, Mathf.Cos(angle * 3 + seed % 11)), 4);
        return .055f + .37f * broad + .13f * secondary;
    }

    private static void CoveBoulders(Sculptor art, float r, uint seed, bool harbor)
    {
        var rng = new SeedRandom(seed + 718);
        for (int cove = 0; cove < 2; cove++)
        {
            float angle = (Mathf.Pi * .5f - seed % 17) * .5f + cove * Mathf.Pi;
            for (int i = 0; i < 3; i++)
            {
                float a = angle + (i - 1) * .18f + rng.Range(-.065f, .065f);
                // Keep the harbor approach clear of decorative rocks.
                if (harbor && Mathf.Sin(a) > .25f && Mathf.Cos(a) > .05f) continue;
                float reach = r * (1.055f * Coast(a, seed) + CoveExtension(a, seed) * rng.Range(.28f, .70f));
                float width = r * rng.Range(.15f, .24f), height = width * rng.Range(.55f, .8f);
                var p = new Vector3(Mathf.Cos(a) * reach, height * .11f, Mathf.Sin(a) * reach);
                // Most of each solid rock intersects the ocean plane, leaving an irregular cap.
                art.Boulder(p, new(width, height, width * rng.Range(.73f, 1.13f)), Stone.Lerp(new Color("47796f"), .48f), rng.Next());
            }
        }
    }

    private static void Land(Sculptor art, float r, uint seed, bool rock)
    {
        const int sides = 64;
        // Transparent outer seabed lets the same moving ocean continue through the shallows.
        float[] radii = [.0f, .63f, .91f, 1.055f, 1.27f, 1.48f];
        float[] heights = [.18f, .17f, .105f, .021f, .006f, .004f];
        Color[] colors = [Sand, Sand, Sand.Darkened(.025f), new("b6a078"), new("327b79"), new("07394b")];
        if (rock) { heights = [.07f, .05f, .025f, .008f, .006f, .004f]; colors = [Stone, Stone, new("7a9d91"), new("45817e"), new("205c65"), new("07394b")]; }
        colors[4] = new Color(colors[4], .72f);
        colors[5] = new Color(colors[4], 0);
        Vector3 Point(int layer, int i)
        {
            float a = i * Mathf.Tau / sides;
            float organic = Coast(a, seed);
            float radius = radii[layer] * organic;
            if (layer >= 4)
            {
                // Wide sand bars occupy unequal coves; the whole coast does not get a necklace.
                float extension = CoveExtension(a, seed);
                radius = 1.055f * organic + extension * (layer == 4 ? .57f : 1);
            }
            float d = Mathf.Min(radius, 1.55f) * r;
            return new(Mathf.Cos(a) * d, heights[layer], Mathf.Sin(a) * d);
        }
        for (int layer = 0; layer < radii.Length - 1; layer++)
            for (int i = 0; i < sides; i++)
            {
                var a = Point(layer, i); var b = Point(layer, i + 1); var c = Point(layer + 1, i + 1); var d = Point(layer + 1, i);
                float grain = .015f * Mathf.Sin(i * 7.7f + seed % 21);
                Color inner = colors[layer].Lightened(grain), outer = colors[layer + 1].Lightened(layer < 3 ? grain : 0);
                Vector3 Normal(Vector3 point, float slope) => new Vector3(point.X / r * slope, 1, point.Z / r * slope).Normalized();
                float slope = layer == 2 ? .40f : .03f;
                art.Triangle(a, b, d, inner, inner, outer, Normal(a, slope), Normal(b, slope), Normal(d, slope), layer >= 3 ? "shelf" : "matte");
                art.Triangle(b, c, d, inner, outer, outer, Normal(b, slope), Normal(c, slope), Normal(d, slope), layer >= 3 ? "shelf" : "matte");
            }
        // Short, broken surf crescents follow a few exposed shore sections only.
        var rng = new SeedRandom(seed + 881);
        for (int patch = 0; patch < (rock ? 3 : 7); patch++)
        {
            float start = patch * Mathf.Tau / (rock ? 3 : 7) + rng.Range(-.22f, .22f);
            float span = rng.Range(.06f, .18f);
            for (int i = 0; i < 5; i++)
            {
                float a = start + span * i / 5, b = start + span * (i + 1) / 5;
                float width = r * .008f * Mathf.Sin((i + .5f) * Mathf.Pi / 5);
                Vector3 P(float t, float offset) => new(Mathf.Cos(t) * (r * 1.06f * Coast(t, seed) + offset), .029f, Mathf.Sin(t) * (r * 1.06f * Coast(t, seed) + offset));
                art.Quad(P(a, 0), P(b, 0), P(b, width), P(a, width), new("a9c4b2"));
            }
        }
    }

    private static void Rock(Sculptor art, Vector3 at, Vector3 size, uint seed)
    {
        var rng = new SeedRandom(seed);
        Color color = Stone.Lightened((seed % 9) * .012f);
        var old = art.Transform;
        art.Transform *= new Transform3D(Basis.FromEuler(new(0, rng.Range(-.55f, .55f), 0)), at);
        if (size.Y < size.X * .85f)
            art.Boulder(new(0, size.Y * .44f, 0), size, color, seed);
        else
        {
            // Broad caps overlap at unequal heights; side buttresses interrupt the main seam.
            art.Boulder(new(size.X * .02f, size.Y * .26f, 0), new(size.X, size.Y * .64f, size.Z * .94f), color, seed);
            art.Boulder(new(-size.X * .13f, size.Y * .71f, -size.Z * .10f), new(size.X * .88f, size.Y * .49f, size.Z * .86f), color.Lightened(.025f), seed + 11);
            art.Boulder(new(-size.X * .32f, size.Y * .25f, size.Z * .24f), new(size.X * .58f, size.Y * .55f, size.Z * .64f), color.Darkened(.025f), seed + 17);
            art.Boulder(new(size.X * .33f, size.Y * .46f, size.Z * .19f), new(size.X * .57f, size.Y * .65f, size.Z * .61f), color.Lightened(.035f), seed + 39);
        }
        art.Transform = old;
    }

    private static void AddCottage(Sculptor art, Vector3 origin, float scale, float yaw)
    {
        // Local transform keeps all cottage details in the same merged material surface.
        var old = art.Transform;
        art.Transform = new Transform3D(Basis.FromEuler(new(0, yaw, 0)).Scaled(Vector3.One * scale), origin);
        Color plaster = new("d4ccad"), trim = new("ece0b7"), wood = new("795538"), roof = new("b8683d"), glass = new("274853");
        art.RoundedBox(new(0, .37f, 0), new(.88f, .74f, .72f), .065f, plaster);
        art.RoundedBox(new(0, .04f, 0), new(.99f, .13f, .81f), .04f, new("aaa68c"));
        // Gable faces under the roof remain full three-dimensional wall geometry.
        art.Face(new(-.45f, .73f, .36f), new(.45f, .73f, .36f), new(0, 1.09f, .36f), plaster);
        art.Face(new(.45f, .73f, -.36f), new(-.45f, .73f, -.36f), new(0, 1.09f, -.36f), plaster);
        for (int side = -1; side <= 1; side += 2)
        {
            for (int strip = 0; strip < 9; strip++)
            {
                float z = -.455f + strip * .113f;
                for (int row = 0; row < 3; row++)
                {
                    float x0 = row * .175f, x1 = (row + 1) * .175f + .023f;
                    Vector3 a = new(side * x0, RoofY(x0), z), b = new(side * x1, RoofY(x1), z);
                    // Individual rounded clay tiles overlap downhill and carry real light/shadow.
                    art.Tile(a, b, .069f, roof.Lightened(((strip * 7 + row * 3) % 5 - 2) * .025f));
                }
            }
        }
        for (int i = 0; i < 8; i++) art.Tube(new(0, 1.14f, -.48f + i * .125f), new(0, 1.14f, -.35f + i * .125f), .058f, .054f, roof.Lightened(.12f), 9);
        art.RoundedBox(new(-.26f, 1.11f, -.22f), new(.16f, .50f, .18f), .025f, new("b6a489"));
        art.RoundedBox(new(-.26f, 1.365f, -.22f), new(.205f, .075f, .23f), .022f, trim);
        art.RoundedBox(new(-.26f, 1.406f, -.22f), new(.09f, .009f, .11f), .006f, new("49483d"));
        Arch(art, new(.12f, .08f, .367f), .285f, .47f, .055f, new("45616a"), trim);
        art.Ellipsoid(new(.17f, .27f, .415f), new(.012f, .012f, .012f), new("c7aa62"), 8, 5);
        Window(art, new(-.235f, .47f, .378f), .16f, .22f, glass, trim);
        Window(art, new(0, .87f, .375f), .115f, .13f, glass, trim);
        // Side window is rotated with the wall, with inset glass and raised timber trim.
        var houseTransform = art.Transform;
        art.Transform = houseTransform * new Transform3D(Basis.FromEuler(new(0, -Mathf.Pi / 2, 0)), new(-.454f, .46f, -.03f));
        Window(art, Vector3.Zero, .19f, .24f, glass, trim);
        art.Transform = houseTransform;
        for (int i = 0; i < 3; i++) art.RoundedBox(new(.12f, .04f - i * .016f, .43f + i * .10f), new(.34f + i * .07f, .055f, .13f), .024f, new("bcb49a"));
        art.Transform = old;
    }

    private static float RoofY(float x) => 1.105f - .71f * x + .06f * x * x;
    private static void Window(Sculptor art, Vector3 p, float width, float height, Color glass, Color trim)
    {
        art.RoundedBox(p, new(width + .055f, height + .055f, .042f), .025f, trim);
        art.RoundedBox(p + new Vector3(0, 0, .025f), new(width, height, .018f), .018f, glass);
        art.RoundedBox(p + new Vector3(0, 0, .039f), new(.017f, height, .021f), .006f, trim);
        art.RoundedBox(p + new Vector3(0, -.01f, .039f), new(width, .015f, .021f), .005f, trim);
        art.RoundedBox(p + new Vector3(0, -height * .58f, .028f), new(width + .08f, .035f, .09f), .012f, trim);
    }

    private static void Arch(Sculptor art, Vector3 p, float width, float height, float depth, Color fill, Color trim)
    {
        float radius = width / 2, spring = height - radius;
        art.RoundedBox(p + new Vector3(0, spring / 2, 0), new(width, spring, depth), .008f, fill);
        for (int i = 0; i < 12; i++)
        {
            float a = i * Mathf.Pi / 12, b = (i + 1) * Mathf.Pi / 12;
            var v1 = p + new Vector3(Mathf.Cos(a) * radius, spring + Mathf.Sin(a) * radius, depth * .5f);
            var v2 = p + new Vector3(Mathf.Cos(b) * radius, spring + Mathf.Sin(b) * radius, depth * .5f);
            art.Face(p + new Vector3(0, spring, depth * .5f), v1, v2, fill);
            art.Tube(v1, v2, .023f, .023f, trim, 6);
        }
        art.Tube(p + new Vector3(-radius, 0, .012f), p + new Vector3(-radius, spring, .012f), .024f, .024f, trim, 6);
        art.Tube(p + new Vector3(radius, 0, .012f), p + new Vector3(radius, spring, .012f), .024f, .024f, trim, 6);
        for (int i = -1; i <= 1; i++) art.RoundedBox(p + new Vector3(i * width * .24f, spring * .47f, depth * .56f), new(.006f, spring * .87f, .006f), .002f, fill.Darkened(.23f));
    }

    private static void Dock(Sculptor art, float r)
    {
        Color timber = new("977145"), cut = new("b19466");
        float x = r * .56f;
        for (int i = 0; i < 11; i++)
            art.RoundedBox(new(x, .145f, r * (.40f + i * .095f)), new(r * .46f, .09f, r * .09f), .018f, timber.Lightened(i % 3 * .03f));
        for (int side = -1; side <= 1; side += 2)
        {
            art.RoundedBox(new(x + side * r * .15f, .072f, r * .88f), new(r * .055f, .10f, r * 1.09f), .01f, timber.Darkened(.12f));
            for (int i = 0; i < 3; i++)
            {
                var bottom = new Vector3(x + side * r * .25f, -.08f, r * (.48f + i * .43f));
                art.Tube(bottom, bottom + new Vector3(0, .47f, 0), r * .049f, r * .042f, timber.Darkened(.09f), 9);
                art.Tube(bottom + new Vector3(0, .455f, 0), bottom + new Vector3(0, .485f, 0), r * .047f, r * .047f, cut, 9);
            }
        }
    }

    private static void Barrel(Sculptor art, Vector3 at, float size)
    {
        art.Ellipsoid(at + new Vector3(0, size * .65f, 0), new(size * .58f, size * .78f, size * .58f), new("977044"), 12, 7);
        for (int i = 0; i < 2; i++) art.Tube(at + new Vector3(0, size * (.27f + i * .78f), 0), at + new Vector3(0, size * (.37f + i * .78f), 0), size * .56f, size * .56f, new("514f42"), 12);
        art.Tube(at + new Vector3(0, size * 1.36f, 0), at + new Vector3(0, size * 1.41f, 0), size * .45f, size * .45f, new("b18b57"), 12);
    }

    private static void Palm(Sculptor art, Vector3 at, float height, uint seed)
    {
        float lean = .13f * height;
        for (int i = 0; i < 7; i++)
        {
            float t = i / 7f, t1 = (i + 1) / 7f;
            art.Tube(at + new Vector3(lean * t * t, height * t, 0), at + new Vector3(lean * t1 * t1, height * t1, 0), height * (.065f - t * .02f), height * (.065f - t1 * .02f), new Color("97774b").Lightened(i % 2 * .065f), 9);
        }
        Vector3 crown = at + new Vector3(lean, height, 0);
        for (int i = 0; i < 8; i++)
        {
            float a = i * Mathf.Tau / 8 + seed % 23;
            Frond(art, crown, a, height * (.62f + .065f * Mathf.Sin(i * 4.7f)), height * .072f, height * .18f, Leaf.Lightened((i % 3) * .035f));
        }
        for (int i = 0; i < 3; i++) art.Ellipsoid(crown + new Vector3((i - 1) * .045f, -.04f, .03f), Vector3.One * height * .045f, new("6d593b"), 8, 5);
    }

    private static void Shrub(Sculptor art, Vector3 at, float size, uint seed)
    {
        for (int i = 0; i < 7; i++)
        {
            float a = i * Mathf.Tau / 7 + seed % 17;
            Frond(art, at, a, size * 1.4f, size * .19f, size * .74f, Leaf.Lightened(i % 3 * .035f));
        }
    }

    private static void Frond(Sculptor art, Vector3 at, float angle, float length, float width, float lift, Color color)
    {
        Vector3 forward = new(Mathf.Cos(angle), 0, Mathf.Sin(angle)), side = new(-forward.Z, 0, forward.X);
        const int steps = 14;
        for (int i = 0; i < steps; i++)
        {
            Vector3 Point(float t, float s)
            {
                // Sin(pi) can round slightly below zero; a fractional power would produce NaN.
                float notch = .89f + .11f * Mathf.Cos(t * steps * Mathf.Pi);
                float w = width * Mathf.Pow(Mathf.Max(0, Mathf.Sin(Mathf.Pi * t)), .8f) * notch;
                return at + forward * (length * t) + Vector3.Up * (lift * Mathf.Sin(Mathf.Pi * t * .9f) - length * .30f * t * t - MathF.Abs(s) * w * .24f) + side * w * s;
            }
            float t = i / (float)steps, n = (i + 1) / (float)steps;
            art.Quad(Point(t, -1), Point(n, -1), Point(n, 0), Point(t, 0), color);
            art.Quad(Point(t, 0), Point(n, 0), Point(n, 1), Point(t, 1), color.Lightened(.04f));
            // Closed underside gives foliage volume from any view, without alpha cards.
            art.Quad(Point(t, 1), Point(n, 1), Point(n, -1), Point(t, -1), color.Darkened(.10f));
            if (width < length * .125f && i < steps - 1 && i % 2 == 0)
                art.Tube(Point(t, 0) + Vector3.Up * .002f, Point(n + 1f / steps, 0) + Vector3.Up * .002f, width * .034f * (1-t), width * .034f * (1-n), color.Lightened(.10f), 5);
        }
    }

    private sealed class Sculptor
    {
        private readonly Dictionary<string, SurfaceTool> surfaces = new();
        public Transform3D Transform = Transform3D.Identity;

        private SurfaceTool Surface(string key)
        {
            if (surfaces.TryGetValue(key, out var found)) return found;
            var surface = new SurfaceTool(); surface.Begin(Mesh.PrimitiveType.Triangles); surfaces.Add(key, surface); return surface;
        }
        public void Triangle(Vector3 a, Vector3 b, Vector3 c, Color ca, Color cb, Color cc, Vector3 na, Vector3 nb, Vector3 nc, string key = "matte")
        {
            Vector3 cross = (b - a).Cross(c - a);
            if (cross.LengthSquared() < 1e-14f) return;
            if (cross.Dot(na + nb + nc) < 0) { (b, c) = (c, b); (nb, nc) = (nc, nb); (cb, cc) = (cc, cb); }
            var s = Surface(key);
            void Vertex(Vector3 p, Color color, Vector3 normal) { s.SetColor(color); s.SetUV(new(p.X, p.Z)); s.SetNormal((Transform.Basis * normal).Normalized()); s.AddVertex(Transform * p); }
            // Godot front faces use clockwise winding. Our geometric normals are explicit.
            Vertex(a, ca, na); Vertex(c, cc, nc); Vertex(b, cb, nb);
        }
        public void Face(Vector3 a, Vector3 b, Vector3 c, Color color)
        {
            Vector3 cross = (b - a).Cross(c - a);
            if (cross.LengthSquared() < 1e-14f) return;
            Vector3 n = cross.Normalized();
            Triangle(a, b, c, color, color, color, n, n, n);
        }
        public void Quad(Vector3 a, Vector3 b, Vector3 c, Vector3 d, Color color) { Face(a, b, c, color); Face(a, c, d, color); }
        public void Ellipsoid(Vector3 p, Vector3 radii, Color color, int sides = 12, int rings = 7)
        {
            Vector3 Unit(int i, int j) { float a = i * Mathf.Tau / sides, b = j * Mathf.Pi / rings; return new(Mathf.Sin(b) * Mathf.Cos(a), Mathf.Cos(b), Mathf.Sin(b) * Mathf.Sin(a)); }
            for (int j = 0; j < rings; j++) for (int i = 0; i < sides; i++)
            {
                var a = Unit(i, j); var b = Unit(i + 1, j); var c = Unit(i + 1, j + 1); var d = Unit(i, j + 1);
                Vector3 Normal(Vector3 q) => new Vector3(q.X / radii.X, q.Y / radii.Y, q.Z / radii.Z).Normalized();
                Triangle(p + a * radii, p + b * radii, p + c * radii, color, color, color, Normal(a), Normal(b), Normal(c));
                Triangle(p + a * radii, p + c * radii, p + d * radii, color, color, color, Normal(a), Normal(c), Normal(d));
            }
        }
        public void RoundedBox(Vector3 p, Vector3 size, float bevel, Color color)
        {
            Vector3 half = size * .5f, inner = half - Vector3.One * Mathf.Min(bevel, Mathf.Min(half.X, Mathf.Min(half.Y, half.Z)) * .95f);
            float radius = half.X - inner.X;
            // Four divisions put flat broad faces between rounded corners, unlike a low-poly sphere.
            float[] cuts = [-1, -.82f, .82f, 1];
            for (int axis = 0; axis < 3; axis++) for (int sign = -1; sign <= 1; sign += 2)
            {
                int u = (axis + 1) % 3, v = (axis + 2) % 3;
                (Vector3 P, Vector3 N) Point(int i, int j)
                {
                    Vector3 raw = Vector3.Zero; raw[axis] = half[axis] * sign; raw[u] = half[u] * cuts[i]; raw[v] = half[v] * cuts[j];
                    Vector3 clamped = raw.Clamp(-inner, inner), normal = (raw - clamped).Normalized();
                    return (p + clamped + normal * radius, normal);
                }
                for (int i = 0; i < 3; i++) for (int j = 0; j < 3; j++)
                {
                    var a = Point(i, j); var b = Point(i + 1, j); var c = Point(i + 1, j + 1); var d = Point(i, j + 1);
                    if (sign < 0) (b, d) = (d, b);
                    Triangle(a.P, b.P, c.P, color, color, color, a.N, b.N, c.N);
                    Triangle(a.P, c.P, d.P, color, color, color, a.N, c.N, d.N);
                }
            }
        }
        public void Boulder(Vector3 p, Vector3 size, Color color, uint seed)
        {
            // Unequal oblique fracture planes define the stone. No box or cylinder is deformed.
            var rng = new SeedRandom(seed);
            var planes = new List<(Vector3 N, float D)>();
            void Plane(Vector3 n, float d) => planes.Add((n.Normalized(), d));
            float phase = rng.Range(-.7f, .7f);
            for (int i = 0; i < 6; i++)
            {
                float angle = phase + i * Mathf.Tau / 6 + rng.Range(-.22f, .22f);
                Plane(new(Mathf.Cos(angle), rng.Range(-.065f, .075f), Mathf.Sin(angle)), rng.Range(.40f, .53f));
            }
            // World-space cap slope is at most atan(sqrt(2)*.12), below 10 degrees.
            // No diagonal upper cutting planes: they previously made pointed triangular caps.
            Plane(new(rng.Range(-.12f, .12f) * size.X / size.Y, 1, rng.Range(-.12f, .12f) * size.Z / size.Y), .40f);
            Plane(new(.17f, -1, -.13f), .46f);
            Plane(new(-.55f, -.74f, -.31f), .53f);
            var vertices = new List<Vector3>();
            for (int i = 0; i < planes.Count; i++) for (int j = i + 1; j < planes.Count; j++) for (int k = j + 1; k < planes.Count; k++)
            {
                var a = planes[i]; var b = planes[j]; var c = planes[k];
                float det = a.N.Dot(b.N.Cross(c.N));
                if (MathF.Abs(det) < .00001f) continue;
                Vector3 q = (b.N.Cross(c.N) * a.D + c.N.Cross(a.N) * b.D + a.N.Cross(b.N) * c.D) / det;
                if (planes.Any(plane => plane.N.Dot(q) > plane.D + .0001f)) continue;
                if (!vertices.Any(v => v.DistanceSquaredTo(q) < .0000001f)) vertices.Add(q);
            }
            var corners = vertices.Select(_ => new List<(Vector3 P, Vector3 N)>()).ToArray();
            var edges = new Dictionary<(int, int), (Vector3 A, Vector3 B, Vector3 N)>();
            float Area(IReadOnlyList<Vector2> points)
            {
                float sum = 0;
                for (int i = 0; i < points.Count; i++) sum += points[i].Cross(points[(i + 1) % points.Count]);
                return MathF.Abs(sum) * .5f;
            }
            var projected = vertices.Select(q => new Vector2(q.X, q.Z)).OrderBy(q => q.X).ThenBy(q => q.Y).ToArray();
            var hull = new List<Vector2>();
            foreach (var q in projected)
            {
                while (hull.Count >= 2 && (hull[^1] - hull[^2]).Cross(q - hull[^1]) <= 0) hull.RemoveAt(hull.Count - 1);
                hull.Add(q);
            }
            int lowerCount = hull.Count;
            for (int i = projected.Length - 2; i >= 0; i--)
            {
                var q = projected[i];
                while (hull.Count > lowerCount && (hull[^1] - hull[^2]).Cross(q - hull[^1]) <= 0) hull.RemoveAt(hull.Count - 1);
                hull.Add(q);
            }
            if (hull.Count > 1) hull.RemoveAt(hull.Count - 1);
            float footprintArea = Area(hull);
            Color Tint(Vector3 point)
            {
                var q = (point - p) / size;
                float cloud = Mathf.Sin(q.X * 9 + q.Z * 7 + seed % 17) * Mathf.Sin(q.Y * 8 - q.Z * 5 + seed % 23);
                float patch = cloud * .065f + .018f * Mathf.Sin(q.X * 23 + q.Y * 18);
                return color.Lightened(patch).Darkened(Mathf.Max(0, -.10f - q.Y) * .10f);
            }
            void Tri(Vector3 a, Vector3 b, Vector3 c, Vector3 na, Vector3 nb, Vector3 nc)
                => Triangle(a, b, c, Tint(a), Tint(b), Tint(c), na, nb, nc);
            foreach (var plane in planes)
            {
                var ids = Enumerable.Range(0, vertices.Count).Where(i => MathF.Abs(plane.N.Dot(vertices[i]) - plane.D) < .0003f).ToList();
                if (ids.Count < 3) continue;
                Vector3 center = ids.Aggregate(Vector3.Zero, (sum, i) => sum + vertices[i]) / ids.Count;
                Vector3 u = (vertices[ids[0]] - center).Normalized(), v = plane.N.Cross(u);
                float Angle(int i) => Mathf.Atan2((vertices[i] - center).Dot(v), (vertices[i] - center).Dot(u));
                ids.Sort((a, b) => Angle(a).CompareTo(Angle(b)));
                Vector3 normal = (plane.N / size).Normalized();
                Vector3 worldCenter = p + center * size;
                // Wide bevel bands target 24% of the minimum dimension. Cap inset is
                // additionally bounded by projected area to preserve a broad top silhouette.
                float bevelWidth = Mathf.Min(size.X, Mathf.Min(size.Y, size.Z)) * .24f;
                float maxInset = .30f;
                if (normal.Y > .9f)
                {
                    float capArea = Area(ids.Select(i => new Vector2(vertices[i].X, vertices[i].Z)).ToArray());
                    maxInset = Mathf.Min(maxInset, Mathf.Max(0, 1 - Mathf.Sqrt(.42f * footprintArea / capArea)));
                }
                var inset = ids.Select(i =>
                {
                    float distance = ((vertices[i] - center) * size).Length();
                    float fraction = Mathf.Min(maxInset, bevelWidth / distance);
                    return p + vertices[i].Lerp(center, fraction) * size;
                }).ToArray();
                for (int i = 0; i < ids.Count; i++)
                {
                    int j = (i + 1) % ids.Count;
                    Tri(worldCenter, inset[i], inset[j], normal, normal, normal);
                    corners[ids[i]].Add((inset[i], normal));
                    var key = (Math.Min(ids[i], ids[j]), Math.Max(ids[i], ids[j]));
                    Vector3 first = ids[i] < ids[j] ? inset[i] : inset[j], second = ids[i] < ids[j] ? inset[j] : inset[i];
                    if (edges.TryGetValue(key, out var other))
                    {
                        Tri(first, second, other.B, normal, normal, other.N);
                        Tri(first, other.B, other.A, normal, other.N, other.N);
                    }
                    else edges[key] = (first, second, normal);
                }
                // A few short, crooked surface fractures terminate within the broad plane.
                if (normal.Y > -.1f && ids[0] % 3 == 0)
                {
                    Vector3 a = worldCenter.Lerp(inset[0], .9f) + normal * .001f;
                    Vector3 b = worldCenter.Lerp(inset[1], .21f) + normal * .001f;
                    Vector3 c = worldCenter.Lerp(inset[^1], .55f) + normal * .001f;
                    Vector3 width = normal.Cross((b-a).Normalized()) * Mathf.Min(size.X, size.Z) * .006f;
                    Triangle(a, b, b + width, color.Darkened(.24f), color.Darkened(.29f), color.Darkened(.16f), normal, normal, normal);
                    Triangle(b, c, b + width, color.Darkened(.29f), color.Darkened(.22f), color.Darkened(.16f), normal, normal, normal);
                }
            }
            foreach (var corner in corners)
            {
                if (corner.Count < 3) continue;
                Vector3 center = corner.Aggregate(Vector3.Zero, (sum, q) => sum + q.P) / corner.Count;
                Vector3 normal = corner.Aggregate(Vector3.Zero, (sum, q) => sum + q.N).Normalized();
                Vector3 u = (corner[0].P - center).Normalized(), v = normal.Cross(u);
                float Angle(Vector3 point) => Mathf.Atan2((point-center).Dot(v), (point-center).Dot(u));
                corner.Sort((a,b) => Angle(a.P).CompareTo(Angle(b.P)));
                for (int i = 0; i < corner.Count; i++) Tri(center, corner[i].P, corner[(i+1)%corner.Count].P, normal, corner[i].N, corner[(i+1)%corner.Count].N);
            }
        }
        public void Tube(Vector3 a, Vector3 b, float ra, float rb, Color color, int sides = 10)
        {
            Vector3 axis = (b - a).Normalized(), u = axis.Cross(MathF.Abs(axis.Y) < .9f ? Vector3.Up : Vector3.Right).Normalized(), v = axis.Cross(u);
            for (int i = 0; i < sides; i++)
            {
                float t = i * Mathf.Tau / sides, q = (i + 1) * Mathf.Tau / sides;
                Vector3 n = u * Mathf.Cos(t) + v * Mathf.Sin(t), m = u * Mathf.Cos(q) + v * Mathf.Sin(q);
                Triangle(a + n * ra, a + m * ra, b + m * rb, color, color, color, n, m, m);
                Triangle(a + n * ra, b + m * rb, b + n * rb, color, color, color, n, m, n);
                Face(a, a + m * ra, a + n * ra, color); Face(b, b + n * rb, b + m * rb, color);
            }
        }
        public void Tile(Vector3 a, Vector3 b, float width, Color color)
        {
            const int divisions = 6;
            Vector3 along = (b - a).Normalized();
            Vector3 up = new(-along.Y * MathF.Sign(along.X), MathF.Abs(along.X), 0);
            for (int i = 0; i < divisions; i++)
            {
                float t = i * Mathf.Pi / divisions, q = (i + 1) * Mathf.Pi / divisions;
                Vector3 n = Vector3.Back * Mathf.Cos(t) + up * Mathf.Sin(t), m = Vector3.Back * Mathf.Cos(q) + up * Mathf.Sin(q);
                Vector3 s = n * width, e = m * width;
                Triangle(a + s, b + s, b + e, color, color, color, n, n, m);
                Triangle(a + s, b + e, a + e, color, color, color, n, m, m);
                Face(b, b + e, b + s, color.Darkened(.035f));
            }
        }
        public Node3D Finish(string name)
        {
            var root = new Node3D { Name = name };
            foreach (var (key, surface) in surfaces)
            {
                if (!Materials.TryGetValue(key, out var material))
                {
                    material = key == "shelf"
                        ? new ShaderMaterial { Shader = GD.Load<Shader>("res://source/presentation/EnvironmentShallows.gdshader") }
                        : TactileSurface.Material;
                    Materials.Add(key, material);
                }
                surface.SetMaterial(material); surface.Index();
                root.AddChild(new MeshInstance3D { Name = key, Mesh = surface.Commit(), CastShadow = key == "shelf" ? GeometryInstance3D.ShadowCastingSetting.Off : GeometryInstance3D.ShadowCastingSetting.On });
                surface.Dispose();
            }
            return root;
        }
    }
}
