using Godot;
using BoatsNBeasts.Core;

namespace BoatsNBeasts;

/// <summary>Seeded, matte miniature scenery. One world unit is 100 simulation units.</summary>
public static class EnvironmentArt3D
{
    private static readonly Color Sand = new("d6bd86"), Stone = new("898b7e"), Leaf = new("647c43");
    private static readonly Dictionary<string, StandardMaterial3D> Materials = new();

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
            for (int i = 0; i < 8; i++)
            {
                float angle = rng.Range(0, Mathf.Tau), reach = rng.Range(.50f, .82f) * r;
                var at = new Vector3(Mathf.Cos(angle) * reach, .13f, Mathf.Sin(angle) * reach);
                if (place.Kind == PlaceKind.Harbor && at.Z > -.05f && at.X > -.4f * r) continue;
                Shrub(art, at, rng.Range(.12f, .21f) * r, rng.Next());
            }
            for (int i = 0; i < 10; i++)
            {
                float angle = rng.Range(0, Mathf.Tau), reach = rng.Range(.72f, .98f) * r;
                float s = rng.Range(.018f, .052f) * r;
                art.Ellipsoid(new(Mathf.Cos(angle) * reach, .09f, Mathf.Sin(angle) * reach), new(s, s * .7f, s * .9f), Stone.Lightened(.08f), 7, 4);
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

    private static void Land(Sculptor art, float r, uint seed, bool rock)
    {
        const int sides = 64;
        // Transparent outer seabed lets the same moving ocean continue through the shallows.
        float[] radii = [.0f, .63f, .91f, 1.055f, 1.22f, 1.35f];
        float[] heights = [.18f, .17f, .105f, .021f, .006f, .004f];
        Color[] colors = [Sand, Sand, Sand, new("b7b48d"), new("327b79"), new("07394b")];
        if (rock) { heights = [.07f, .05f, .025f, .008f, .006f, .004f]; colors = [Stone, Stone, new("7a9d91"), new("45817e"), new("205c65"), new("07394b")]; }
        colors[4] = new Color(colors[4], .42f);
        colors[5] = new Color(colors[4], 0);
        Vector3 Point(int layer, int i)
        {
            float a = i * Mathf.Tau / sides;
            float organic = Coast(a, seed);
            if (layer >= 4) organic += .026f * Mathf.Sin(a * 9 + seed % 7);
            float d = Mathf.Min(radii[layer] * organic, 1.55f) * r;
            return new(Mathf.Cos(a) * d, heights[layer], Mathf.Sin(a) * d);
        }
        for (int layer = 0; layer < radii.Length - 1; layer++)
            for (int i = 0; i < sides; i++)
            {
                var a = Point(layer, i); var b = Point(layer, i + 1); var c = Point(layer + 1, i + 1); var d = Point(layer + 1, i);
                float grain = .015f * Mathf.Sin(i * 7.7f + seed % 21);
                Color inner = colors[layer].Lightened(grain), outer = colors[layer + 1].Lightened(layer < 3 ? grain : 0);
                art.Triangle(a, b, d, inner, inner, outer, Vector3.Up, Vector3.Up, Vector3.Up, layer >= 3 ? "shelf" : "matte");
                art.Triangle(b, c, d, inner, outer, outer, Vector3.Up, Vector3.Up, Vector3.Up, layer >= 3 ? "shelf" : "matte");
            }
    }

    private static void Rock(Sculptor art, Vector3 at, Vector3 size, uint seed)
    {
        var rng = new SeedRandom(seed);
        const int n = 9;
        float[] profile = [.78f, 1, .94f, .82f, .56f];
        float[] levels = [0, .15f, .57f, .88f, 1];
        var ring = new Vector3[5, n];
        float phase = rng.Range(0, Mathf.Tau);
        for (int l = 0; l < 5; l++)
            for (int i = 0; i < n; i++)
            {
                float a = i * Mathf.Tau / n + phase;
                float radial = profile[l] * (.91f + .13f * Mathf.Sin(i * 4.8f + seed % 11));
                ring[l, i] = at + new Vector3(Mathf.Cos(a) * size.X * .5f * radial + size.X * l * .021f, size.Y * (levels[l] + (l > 0 ? rng.Range(-.022f, .022f) : 0)), Mathf.Sin(a) * size.Z * .5f * radial);
            }
        Color color = Stone.Lightened((seed % 9) * .012f);
        for (int l = 0; l < 4; l++)
            for (int i = 0; i < n; i++)
            {
                int j = (i + 1) % n;
                Color face = color.Darkened(l == 0 ? .08f : 0).Lightened(.024f * Mathf.Sin(i * 3.2f));
                art.Quad(ring[l, i], ring[l + 1, i], ring[l + 1, j], ring[l, j], face);
            }
        Vector3 top = at + new Vector3(size.X * .08f, size.Y * 1.012f, 0);
        for (int i = 0; i < n; i++) art.Face(ring[4, i], top, ring[4, (i + 1) % n], color.Lightened(.045f));
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
        Arch(art, new(.12f, .08f, .367f), .25f, .43f, .04f, wood, trim);
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
            Frond(art, crown, a, height * (.48f + .055f * Mathf.Sin(i * 4.7f)), height * .12f, height * .18f, Leaf.Lightened((i % 3) * .06f));
        }
        for (int i = 0; i < 3; i++) art.Ellipsoid(crown + new Vector3((i - 1) * .045f, -.04f, .03f), Vector3.One * height * .045f, new("6d593b"), 8, 5);
    }

    private static void Shrub(Sculptor art, Vector3 at, float size, uint seed)
    {
        for (int i = 0; i < 7; i++)
        {
            float a = i * Mathf.Tau / 7 + seed % 17;
            Frond(art, at, a, size * 1.2f, size * .30f, size * .85f, Leaf.Lightened(i % 3 * .06f));
        }
    }

    private static void Frond(Sculptor art, Vector3 at, float angle, float length, float width, float lift, Color color)
    {
        Vector3 forward = new(Mathf.Cos(angle), 0, Mathf.Sin(angle)), side = new(-forward.Z, 0, forward.X);
        const int steps = 7;
        for (int i = 0; i < steps; i++)
        {
            Vector3 Point(float t, float s)
            {
                // Sin(pi) can round slightly below zero; a fractional power would produce NaN.
                float w = width * Mathf.Pow(Mathf.Max(0, Mathf.Sin(Mathf.Pi * t)), .8f);
                return at + forward * (length * t) + Vector3.Up * (lift * Mathf.Sin(Mathf.Pi * t * .9f) - length * .18f * t * t - MathF.Abs(s) * w * .20f) + side * w * s;
            }
            float t = i / (float)steps, n = (i + 1) / (float)steps;
            art.Quad(Point(t, -1), Point(n, -1), Point(n, 0), Point(t, 0), color);
            art.Quad(Point(t, 0), Point(n, 0), Point(n, 1), Point(t, 1), color.Lightened(.04f));
            // Closed underside gives foliage volume from any view, without alpha cards.
            art.Quad(Point(t, 1), Point(n, 1), Point(n, -1), Point(t, -1), color.Darkened(.10f));
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
            void Vertex(Vector3 p, Color color, Vector3 normal) { s.SetColor(color); s.SetNormal((Transform.Basis * normal).Normalized()); s.AddVertex(Transform * p); }
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
                    material = new StandardMaterial3D { VertexColorUseAsAlbedo = true, VertexColorIsSrgb = true, Roughness = .93f, CullMode = BaseMaterial3D.CullModeEnum.Disabled };
                    if (key == "shelf")
                    {
                        material.ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded;
                        material.Transparency = BaseMaterial3D.TransparencyEnum.Alpha;
                    }
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
