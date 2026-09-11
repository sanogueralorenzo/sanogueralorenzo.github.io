using Godot;
using BoatsNBeasts.Core;

namespace BoatsNBeasts;

/// <summary>Seeded coastal terrain and island compositions. One world unit is 100 simulation units.</summary>
public static partial class EnvironmentArt3D
{
    private static readonly Color Sand = new("edce8f"), Stone = new("64747b"), Leaf = new("538844");
    private static readonly Dictionary<string, Material> Materials = new();

    public static Node3D Build(Place place, LandmarkSizes? landmarkSizes = null)
    {
        var art = new Sculptor { Sizes = landmarkSizes ?? new LandmarkSizes() };
        var rng = new SeedRandom(place.Style);
        float r = place.Radius * .01f;
        if (place.Kind == PlaceKind.Shipwreck)
        {
            float scale = place.Radius / OceanWorld.ShipwreckUnitRadius;
            art.Transform = new Transform3D(Basis.FromEuler(new(0, OceanWorld.ShipwreckHeading, 0)).Scaled(Vector3.One * scale), new(0, -.12f * scale, 0));
            Shipwreck(art, afloat: true);
        }
        else if (place.Kind == PlaceKind.Rock)
        {
            Land(art, r * .88f, place.Style, true);
            Rock(art, new(0, .04f, 0), new(r * 1.7f, r * 1.65f, r * 1.5f), place.Style);
            Rock(art, new(-r * .48f, .01f, r * .5f), new(r * .8f, r * .65f, r * .7f), place.Style + 21);
        }
        else if (place.Kind is PlaceKind.Harbor or PlaceKind.Island)
        {
            Land(art, r, place.Style, false, place.Shape);
            art.Footprint = place.Shape;
            art.BeachReserve = BeachWidth(r, place.Style);
            art.HeightScale = place.Shape == null ? 1 : MathF.Min(1, 2.1f / r) * .78f;
            if (OceanWorld.IslandTreasure(place) is { } treasure)
                art.TreasureSpace = (treasure.Position - place.Position) * .01f;
            if (place.Kind == PlaceKind.Harbor)
            {
                AddCottage(art, new(-r * .15f, .18f, -r * .06f), r * .67f, -.20f);
                Dock(art, r);
                for (int i = 0; i < 4; i++)
                {
                    var at = new Vector3((-.56f + i * .29f) * r, .14f, (-.51f - .10f * Mathf.Sin(i * 2)) * r);
                    Rock(art, at, new(r * .52f, r * (.38f + i % 2 * .25f), r * .46f), place.Style + (uint)i * 21);
                    Palm(art, at + new Vector3(-r * .055f, r * .17f, -r * .045f), r * (.75f + i % 3 * .14f), place.Style + (uint)i * 33);
                    Shrub(art, at + new Vector3(r * .08f, .10f, r * .17f), r * .21f, place.Style + (uint)i);
                }
                Palm(art, new(-r * .64f, .17f, r * .12f), r * .73f, place.Style + 88);
                Rock(art, new(-r * .58f, .09f, r * .50f), new(r * .39f, r * .27f, r * .36f), place.Style + 2);
                Barrel(art, new(r * .35f, .18f, r * .32f), r * .16f);
                Barrel(art, new(r * .55f, .16f, r * .25f), r * .13f);
                HarborDetails(art, r);
            }
            else
            {
                IslandInterior(art, r, place.Style);
            }
            for (int i = 0; i < 12; i++)
            {
                float angle = rng.Range(0, Mathf.Tau), reach = rng.Range(.4f, .7f) * r;
                var at = new Vector3(Mathf.Cos(angle) * reach, .13f, Mathf.Sin(angle) * reach);
                if (place.Kind == PlaceKind.Harbor && at.Z > -.36f * r && at.X > -.50f * r) continue;
                Shrub(art, at, rng.Range(.12f, .20f) * r, rng.Next());
            }
            ShoreRocks(art, r, place.Style, place.Kind == PlaceKind.Harbor);
        }
        return art.Finish("Environment_" + place.Kind);
    }

    // Unit-scale cottage with its origin at floor level.
    public static Node3D Cottage()
    {
        var art = new Sculptor();
        AddCottage(art, Vector3.Zero, 1, -.20f);
        return art.Finish("Cottage");
    }

    // Keep visible land inside the shared collision outline.
    private static float Coast(float a, uint seed) => Mathf.Clamp(.918f + .074f * Mathf.Sin(a * 2 + seed % 17)
        + .054f * Mathf.Cos(a * 3 + seed % 11) + .034f * Mathf.Sin(a * 5 + seed % 7) + .014f * Mathf.Cos(a * 9), .80f, 1.01f);

    // World-space clearance from the dry sand edge, shared by terrain and props.
    private static float BeachWidth(float r, uint seed) => Math.Clamp(r * .055f, .06f, .18f)
        * new SeedRandom(seed ^ 0x5a17u).Range(.65f, 1.35f);
    private static float InlandClearance(IslandShape shape, Vector2 point)
    {
        const float dryCoast = .965f;
        return shape.Overlap(new(point.X * 100 / dryCoast, point.Y * 100 / dryCoast), 0, out _, out float depth)
            ? depth * .01f * dryCoast : 0;
    }

    private static void IslandLand(Sculptor art, IslandShape shape, float r, uint seed)
    {
        int layers = Math.Max(24, (int)MathF.Ceiling(r / .12f));
        var points = new Vector3[layers + 1, IslandShape.Sides];
        var clearance = new float[layers + 1, IslandShape.Sides];
        var margins = new float[layers + 1, IslandShape.Sides];
        float beach = BeachWidth(r, seed);
        for (int layer = 0; layer <= layers; layer++) for (int i = 0; i < IslandShape.Sides; i++)
        {
            float reach = layer / (float)layers * 1.02f;
            var p = shape.Shore[i] * (.01f * reach);
            float d = InlandClearance(shape, new(p.X, p.Y));
            clearance[layer, i] = d;
            float height = reach > .965f ? Mathf.Lerp(.018f, .007f, (reach - .965f) / .055f)
                : Mathf.Lerp(.018f, .20f, Mathf.SmoothStep(0, beach + .28f, d));
            points[layer, i] = new(p.X, height, p.Y);
        }
        void VisitTriangles(Action<int, int, int, int, int, int> visit)
        {
            for (int layer = 0; layer < layers; layer++) for (int i = 0; i < IslandShape.Sides; i++)
            {
                int next = (i + 1) % IslandShape.Sides;
                visit(layer, i, layer, next, layer + 1, i);
                visit(layer, next, layer + 1, next, layer + 1, i);
            }
        }
        VisitTriangles((la, ia, lb, ib, lc, ic) =>
        {
            var a = points[la, ia]; var b = points[lb, ib]; var c = points[lc, ic];
            // Distance is 1-Lipschitz: this margin keeps even interpolated grass
            // outside the reserved beach, including triangles spanning a concave bay.
            float margin = MathF.Max(a.DistanceTo(b), MathF.Max(b.DistanceTo(c), c.DistanceTo(a)));
            margins[la, ia] = MathF.Max(margins[la, ia], margin);
            margins[lb, ib] = MathF.Max(margins[lb, ib], margin);
            margins[lc, ic] = MathF.Max(margins[lc, ic], margin);
        });
        // Interpolate a conservative inland distance, then diffuse the color in
        // the ground shader so the grass edge does not follow individual triangles.
        float blendWidth = Math.Clamp(r * .24f, .30f, 1.35f);
        Vector2 GroundUv(int layer, int i) => new(clearance[layer, i] - margins[layer, i] - beach, blendWidth);
        VisitTriangles((la, ia, lb, ib, lc, ic) =>
            art.Triangle(points[la, ia], points[lb, ib], points[lc, ic], Sand, Sand, Sand,
                Vector3.Up, Vector3.Up, Vector3.Up, "ground", GroundUv(la, ia), GroundUv(lb, ib), GroundUv(lc, ic)));
    }

    private static void Land(Sculptor art, float r, uint seed, bool rock, IslandShape? shape = null)
    {
        const int sides = IslandShape.Sides;
        float[] radii = [0, .43f, .66f, .82f, .965f, 1.02f];
        float[] heights = [.20f, .19f, .15f, .09f, .018f, .007f];
        Color[] colors = [new("6b8d43"), new("75934a"), new("a4aa62"), Sand, new("f4dca1"), new("aabda0")];
        Vector3 CoastPoint(float angle, float scale, float height)
        {
            var p = shape?.Point(angle) * .0104f ?? new System.Numerics.Vector2(Mathf.Cos(angle), Mathf.Sin(angle)) * (r * Coast(angle, seed));
            return new(p.X * scale, height, p.Y * scale);
        }
        Vector3 Point(int layer, int i)
        {
            float a = i * Mathf.Tau / sides;
            // Even at their extrema, inland layers stay inside the beach layer.
            float inland = layer is 1 or 2 ? 1 + .10f * Mathf.Sin(a * 3 + seed % 9) + .05f * Mathf.Cos(a * 5)
                : layer == 3 ? 1 + .06f * Mathf.Sin(a * 4 + seed % 9) : 1;
            float reach = radii[layer] * inland;
            return CoastPoint(a, reach, heights[layer]);
        }
        if (!rock && shape != null) IslandLand(art, shape, r, seed);
        if (!rock && shape == null) for (int layer = 0; layer < radii.Length - 1; layer++)
            for (int i = 0; i < sides; i++)
            {
                var a=Point(layer,i); var b=Point(layer,i+1); var c=Point(layer+1,i+1); var d=Point(layer+1,i);
                art.Triangle(a,b,d,colors[layer],colors[layer],colors[layer+1],Vector3.Up,Vector3.Up,Vector3.Up);
                art.Triangle(b,c,d,colors[layer],colors[layer+1],colors[layer+1],Vector3.Up,Vector3.Up,Vector3.Up);
            }
        // Offset the actual coastline by a world-space distance. Radial scaling
        // collapses shallows along inward-facing bays and narrow island axes.
        var coast = Enumerable.Range(0, sides).Select(i =>
        {
            var p = CoastPoint(i * Mathf.Tau / sides, .98f, .014f);
            return new Vector2(p.X, p.Z);
        }).ToArray();
        float shelfWidth = Math.Clamp(r * .60f, .50f, 2.8f)
            * new SeedRandom(seed ^ 0x4ee7u).Range(.90f, 1.10f);
        var shelf = new Vector3[9, sides];
        for (int layer = 0; layer <= 8; layer++)
        {
            if (layer == 0)
            {
                for (int i = 0; i < sides; i++) shelf[layer, i] = new(coast[i].X, .014f, coast[i].Y);
                continue;
            }
            var outlines = Geometry2D.OffsetPolygon(coast, shelfWidth * layer / 8f, Geometry2D.PolyJoinType.Round);
            for (int i = 0; i < sides; i++)
            {
                var direction = Vector2.FromAngle(i * Mathf.Tau / sides);
                float reach = 0;
                // All shore outlines are star-shaped about their origin. Resample
                // each outward offset on the same rays to join rings without folds.
                foreach (var outline in outlines) for (int j = 0; j < outline.Length; j++)
                {
                    var start = outline[j]; var edge = outline[(j + 1) % outline.Length] - start;
                    float divisor = direction.Cross(edge);
                    if (MathF.Abs(divisor) < .000001f) continue;
                    float along = start.Cross(direction) / divisor, distance = start.Cross(edge) / divisor;
                    if (along >= -.00001f && along <= 1.00001f && distance > 0) reach = MathF.Max(reach, distance);
                }
                if (reach <= 0) throw new InvalidOperationException($"Invalid shelf contour for island seed {seed}.");
                shelf[layer, i] = new(direction.X * reach, .014f, direction.Y * reach);
            }
        }
        // Smooth variation follows coastline length rather than polar angle, so
        // one narrow bay does not receive all the variation compressed into it.
        var widths = new float[sides];
        var alongCoast = new float[sides];
        float perimeter = 0;
        for (int i = 1; i < sides; i++)
        {
            perimeter += coast[i - 1].DistanceTo(coast[i]);
            alongCoast[i] = perimeter;
        }
        perimeter += coast[^1].DistanceTo(coast[0]);
        var shelfRng = new SeedRandom(seed ^ 0x7c31u);
        float phaseA = shelfRng.Range(0, Mathf.Tau), phaseB = shelfRng.Range(0, Mathf.Tau), phaseC = shelfRng.Range(0, Mathf.Tau);
        for (int i = 0; i < sides; i++)
        {
            float a = alongCoast[i] / perimeter * Mathf.Tau;
            widths[i] = Math.Clamp(.78f + .12f * MathF.Sin(2 * a + phaseA)
                + .07f * MathF.Sin(3 * a + phaseB) + .03f * MathF.Sin(5 * a + phaseC), .56f, 1);
        }
        // Sample within nested true offsets: no crossing strips or sharp joins.
        Vector3 ShelfPoint(int layer, int i)
        {
            i %= sides;
            float at = layer * widths[i];
            int inner = (int)at;
            return shelf[inner, i].Lerp(shelf[Math.Min(8, inner + 1), i], at - inner);
        }
        float CoastAngle(int i) => (i == sides ? 1 : alongCoast[i] / perimeter) * Mathf.Tau;
        for (int layer = 0; layer < 8; layer++) for (int i = 0; i < sides; i++)
        {
            var a = ShelfPoint(layer, i); var b = ShelfPoint(layer, i + 1);
            var c = ShelfPoint(layer + 1, i + 1); var d = ShelfPoint(layer + 1, i);
            Vector2 U(int l, int n) => new(CoastAngle(n) + seed % 23, l / 8f);
            var color = new Color("66c9bd");
            art.Triangle(a,b,d,color,color,color,Vector3.Up,Vector3.Up,Vector3.Up,"shelf",U(layer,i),U(layer,i+1),U(layer+1,i));
            art.Triangle(b,c,d,color,color,color,Vector3.Up,Vector3.Up,Vector3.Up,"shelf",U(layer,i+1),U(layer+1,i+1),U(layer+1,i));
        }
    }

    private static void ShoreRocks(Sculptor art, float r, uint seed, bool harbor)
    {
        var rng = new SeedRandom(seed + 709);
        int count = harbor ? 11 : Math.Max(11, (int)MathF.Ceiling(r / 3.6f * 11));
        for (int i = 0; i < count; i++)
        {
            float a = rng.Range(0, Mathf.Tau);
            // The working waterfront stays open between cottage, barrels and dock.
            if (harbor && Mathf.Cos(a) > -.25f && Mathf.Sin(a) > -.3f) continue;
            float reach = Coast(a, seed) * r * .85f, size = rng.Range(.20f, .38f) * r;
            var at = new Vector3(Mathf.Cos(a) * reach, .018f, Mathf.Sin(a) * reach);
            Rock(art, at, new(size, size * rng.Range(.6f, 1.2f), size * .82f), rng.Next(), moss: i % 3 == 0);
        }
    }

    private static void IslandInterior(Sculptor art, float r, uint seed)
    {
        if (SettlementInterior(art, r, seed)) return;
        int kind = (int)(seed % 3);
        var rng = new SeedRandom(seed + 117);
        int count = kind == 1 ? 4 : 8;
        for (int i = 0; i < count; i++)
        {
            float a = i * 2.3f + seed % 11, reach = rng.Range(.15f, .48f) * r;
            float height = r * (kind == 2 ? rng.Range(.65f, 1.35f) : rng.Range(.25f, .66f));
            var at = new Vector3(Mathf.Cos(a) * reach - r * .10f, .13f, Mathf.Sin(a) * reach - r * .15f);
            Rock(art, at, new(r * rng.Range(.45f, .71f), height, r * rng.Range(.42f, .66f)), rng.Next(), moss: true);
        }
        if (kind == 0)
        {
            Ruin(art, new(-r * .24f, .17f, -r * .23f), r * 1.02f, -.12f, seed);
            Ruin(art, new(r * .40f, .12f, r * .18f), r * .70f, .24f, seed + 19);
            for (int i = 0; i < 3; i++)
            {
                var old = art.PlaceProp(new((-.22f + i * .18f) * r, .205f, r * .50f), r * .13f);
                art.RoundedBox(Vector3.Zero, new(r * .19f, .09f, r * .15f), .015f, new("a5a28a"));
                art.EndProp(old);
            }
        }
        int palms = kind == 0 ? 3 : kind == 1 ? 7 : 4;
        for (int i = 0; i < palms; i++)
        {
            float a = kind == 0 ? -.68f - i * 2.05f : .10f + i * 1.83f;
            float reach = r * (kind == 0 ? .55f : i % 2 == 0 ? .56f : .35f);
            var at = new Vector3(Mathf.Cos(a) * reach, .16f, Mathf.Sin(a) * reach);
            Palm(art, at, r * (kind == 0 ? rng.Range(.58f, .76f) : rng.Range(.64f, 1.03f)), rng.Next());
            Shrub(art, at + new Vector3(-r * .07f, 0, r * .02f), r * .19f, rng.Next());
        }
        // Keep tree and rock scale familiar; add planted groups across the extra land.
        int groups = Math.Max(0, (int)MathF.Ceiling((r * r - 3.6f * 3.6f) * .30f));
        for (int i = 0; i < groups; i++)
        {
            float a = i * 2.39996f + rng.Range(-.25f, .25f), reach = r * rng.Range(.36f, .78f);
            var at = new Vector3(MathF.Cos(a) * reach, .14f, MathF.Sin(a) * reach);
            Rock(art, at, new(r * .30f, r * rng.Range(.30f, .58f), r * .28f), rng.Next(), moss: true);
            Palm(art, at + new Vector3(r * .05f, .01f, -r * .03f), r * rng.Range(.60f, .86f), rng.Next());
            if (kind == 1) Palm(art, at + new Vector3(-r * .04f, .01f, r * .05f), r * .60f, rng.Next());
            Shrub(art, at + new Vector3(r * .045f, 0, r * .055f), r * .22f, rng.Next());
            Shrub(art, at + new Vector3(-r * .04f, 0, -r * .055f), r * .18f, rng.Next());
        }
    }

    private static void Ruin(Sculptor art, Vector3 at, float scale, float yaw, uint seed)
    {
        var old = art.PlaceProp(at, scale * .55f);
        art.Transform *= new Transform3D(Basis.FromEuler(new(0, yaw, -.035f)).Scaled(Vector3.One * scale), Vector3.Zero);
        var stone = new Color("7c8985");
        art.Boulder(new(0, .87f, 0), new(.65f, 1.82f, .58f), stone, seed);
        art.RoundedBox(new(0, .56f, .25f), new(.46f, .78f, .10f), .055f, stone.Darkened(.19f));
        for (int i = 0; i < 24; i++)
        {
            float a = i * Mathf.Tau * 1.6f / 24, b = (i + 1) * Mathf.Tau * 1.6f / 24;
            float ra = .14f * (1 - i / 31f), rb = .14f * (1 - (i + 1) / 31f);
            art.Tube(new(Mathf.Cos(a) * ra, .71f + Mathf.Sin(a) * ra, .311f), new(Mathf.Cos(b) * rb, .71f + Mathf.Sin(b) * rb, .311f), .012f, .012f, new("b9c5ab"), 4);
        }
        Vector3[] mark = [new(-.12f,.31f,.311f),new(-.12f,.46f,.311f),new(0,.52f,.311f),new(.12f,.46f,.311f),new(.12f,.31f,.311f)];
        for (int i = 0; i < mark.Length - 1; i++) art.Tube(mark[i], mark[i+1], .014f, .014f, new("b9c5ab"), 4);
        Shrub(art, new(-.07f, 1.75f, -.025f), .23f, seed + 3);
        art.EndProp(old);
    }

    private static void HarborDetails(Sculptor art, float r)
    {
        for (int i = 0; i < 4; i++)
        {
            var p = new Vector3((.08f + i * .12f) * r, .18f - i * .015f, (.20f + i * .06f) * r);
            art.Boulder(p, new(r * .15f, .04f, r * .11f), new("c4b994"), (uint)(31 + i));
        }
    }

    public static void Advance(float clock)
    {
        if (Materials.TryGetValue("shelf", out var material) && material is ShaderMaterial shader)
            shader.SetShaderParameter("clock", clock);
    }

    private static void Rock(Sculptor art, Vector3 at, Vector3 size, uint seed, bool moss = false)
    {
        var rng = new SeedRandom(seed);
        Color color = Stone.Lightened((seed % 9) * .012f);
        var old = art.PlaceProp(at, MathF.Max(size.X, size.Z) * .80f);
        art.Transform *= new Transform3D(Basis.FromEuler(new(0, rng.Range(-.55f, .55f), 0)), Vector3.Zero);
        art.Boulder(new(0, size.Y * .48f, 0), size, color, seed);
        if (moss) Shrub(art, new(0, size.Y * .94f, 0), MathF.Min(size.X, size.Z) * .23f, seed + 11);
        art.EndProp(old);
    }

    private static void AddCottage(Sculptor art, Vector3 origin, float scale, float yaw)
    {
        // Local transform keeps all cottage details in the same merged material surface.
        var old = art.Transform;
        art.Transform = new Transform3D(Basis.FromEuler(new(0, yaw, 0)).Scaled(Vector3.One * scale), origin);
        Color plaster = new("d4ccad"), trim = new("ece0b7"), wood = new("795538"), roof = new("b8683d"), glass = new("274853");
        art.RoundedBox(new(0, .37f, 0), new(.88f, .74f, .72f), .065f, plaster);
        art.RoundedBox(new(0, .04f, 0), new(.99f, .13f, .81f), .04f, new("aaa68c"));
        art.Face(new(-.45f, .73f, .36f), new(.45f, .73f, .36f), new(0, 1.09f, .36f), plaster);
        art.Face(new(.45f, .73f, -.36f), new(-.45f, .73f, -.36f), new(0, 1.09f, -.36f), plaster);
        for (int side = -1; side <= 1; side += 2)
        {
            float z=side*.47f;
            art.Quad(new(0,1.13f,z),new(side*.56f,.73f,z),new(side*.56f,.73f,-z),new(0,1.13f,-z),roof);
            art.Tube(new(side*.56f,.72f,-.48f),new(side*.56f,.72f,.48f),.025f,.025f,roof.Darkened(.12f),4);
        }
        art.Tube(new(0,1.13f,-.48f),new(0,1.13f,.48f),.03f,.03f,roof.Lightened(.08f),4);
        art.RoundedBox(new(-.26f, 1.11f, -.22f), new(.16f, .50f, .18f), .025f, new("b6a489"));
        art.RoundedBox(new(-.26f, 1.365f, -.22f), new(.205f, .075f, .23f), .022f, trim);
        art.RoundedBox(new(-.26f, 1.406f, -.22f), new(.09f, .009f, .11f), .006f, new("49483d"));
        Arch(art, new(.12f, .08f, .367f), .285f, .47f, .055f, new("45616a"), trim);
        art.Ellipsoid(new(.17f, .27f, .415f), new(.012f, .012f, .012f), new("c7aa62"), 8, 5);
        Window(art, new(-.235f, .47f, .378f), .16f, .22f, glass, trim);
        Window(art, new(0, .87f, .375f), .115f, .13f, glass, trim);
        var houseTransform = art.Transform;
        art.Transform = houseTransform * new Transform3D(Basis.FromEuler(new(0, -Mathf.Pi / 2, 0)), new(-.454f, .46f, -.03f));
        Window(art, Vector3.Zero, .19f, .24f, glass, trim);
        art.Transform = houseTransform;
        for (int i = 0; i < 3; i++) art.RoundedBox(new(.12f, .04f - i * .016f, .43f + i * .10f), new(.34f + i * .07f, .055f, .13f), .024f, new("bcb49a"));
        art.Transform = old;
    }

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
        // Include the full leaning crown, not just the trunk.
        var old = art.PlaceProp(at, height * .90f);
        at = Vector3.Zero;
        float lean = (.10f + seed % 7 * .022f) * height;
        float yaw = seed % 29;
        var bend = new Vector3(Mathf.Cos(yaw), 0, Mathf.Sin(yaw)) * lean;
        for (int i = 0; i < 5; i++)
        {
            float t = i / 5f, t1 = (i + 1) / 5f;
            art.Tube(at + bend * t * t + Vector3.Up * height * t, at + bend * t1 * t1 + Vector3.Up * height * t1,
                height * (.045f - t * .022f), height * (.045f - t1 * .022f), new Color("8a7044").Lightened(i % 2 * .085f), 7);
        }
        Vector3 crown = at + bend + Vector3.Up * height;
        for (int i = 0; i < 9; i++)
        {
            float a = i * Mathf.Tau / 9 + seed % 23;
            Frond(art, crown, a, height * (.52f + .11f * Mathf.Sin(i * 4.7f)), height * .10f, height * (.18f + i % 3 * .035f),
                Leaf.Lerp(new Color("bbc24f"), (i % 4) * .19f));
        }
        for (int i = 0; i < 3; i++) art.Ellipsoid(crown + new Vector3((i - 1) * .045f, -.04f, .03f), Vector3.One * height * .045f, new("6d593b"), 8, 5);
        art.EndProp(old);
    }

    private static void Shrub(Sculptor art, Vector3 at, float size, uint seed)
    {
        var old = art.PlaceProp(at, size * 1.25f);
        at = Vector3.Zero;
        var green = Leaf.Lerp(new Color("a2b44d"), seed % 5 * .11f);
        art.Boulder(at+Vector3.Up*size*.35f,new(size*1.4f,size,size),green,seed);
        art.Boulder(at+new Vector3(size*.4f,size*.2f,size*.15f),new(size,size*.7f,size),green.Lightened(.1f),seed+7);
        for (int i = 0; i < 4; i++) Frond(art, at + Vector3.Up * size * .18f, i * 2.4f + seed % 13,
            size * .84f, size * .19f, size * .6f, green.Lightened(i % 2 * .13f));
        art.EndProp(old);
    }

    private static void Frond(Sculptor art, Vector3 at, float angle, float length, float width, float lift, Color color)
    {
        Vector3 forward=new(Mathf.Cos(angle),0,Mathf.Sin(angle)), side=new(-forward.Z,0,forward.X);
        for (int i = 0; i < 5; i++)
        {
            (Vector3 L, Vector3 C, Vector3 R) Section(float t)
            {
                float w = width * Mathf.Sin(Mathf.Pi * t) * (1 - t * .28f);
                var center = at + forward * length * t + Vector3.Up * (Mathf.Sin(Mathf.Pi * t) * lift - length * .23f * t * t);
                return (center-side*w,center+Vector3.Up*w*.28f,center+side*w);
            }
            var a = Section(i / 5f); var b = Section((i + 1) / 5f);
            art.Quad(a.L,a.C,b.C,b.L,color); art.Quad(a.C,a.R,b.R,b.C,color.Lightened(.13f));
        }
    }

    private sealed class Sculptor
    {
        private readonly Dictionary<string, SurfaceTool> surfaces = new();
        public Transform3D Transform = Transform3D.Identity;
        // Fit props after terrain; nested details inherit the fitted parent transform.
        public IslandShape? Footprint;
        public LandmarkSizes Sizes = new();
        public float HeightScale = 1;
        public float BeachReserve;
        public System.Numerics.Vector2? TreasureSpace;
        public (Vector2 Center, float Radius)? LandmarkSpace;
        public (Vector2 Start, Vector2 End, float Width)? JettySpace;
        private int propDepth;
        private int hiddenPropDepth;
        public Transform3D BeginWorldProp()
        {
            var old = Transform;
            Transform = Transform3D.Identity; propDepth++;
            return old;
        }
        public Transform3D PlaceProp(Vector3 at, float footprintRadius)
        {
            var old = Transform;
            float scale = 1;
            if (Footprint != null && propDepth == 0)
            {
                var p = Footprint.PlaceOnLand(new(at.X * 100, at.Z * 100));
                at = new(p.X * .01f, at.Y, p.Y * .01f);
                scale = HeightScale;
                float available = InlandClearance(Footprint, new(at.X, at.Z)) - BeachReserve;
                scale = MathF.Min(scale, MathF.Max(0, available) / footprintRadius);
                var center = new Vector2(p.X * .01f, p.Y * .01f);
                if (LandmarkSpace is { } landmark && center.DistanceTo(landmark.Center) < landmark.Radius + footprintRadius * scale)
                    hiddenPropDepth = propDepth + 1;
                if (JettySpace is { } jetty && center.DistanceTo(Geometry2D.GetClosestPointToSegment(center, jetty.Start, jetty.End)) < jetty.Width + footprintRadius * scale)
                    hiddenPropDepth = propDepth + 1;
                // A narrow spit may support sand only; omit props instead of squeezing
                // them onto the shoreline or leaving barely visible miniature rocks.
                if (scale < HeightScale * .30f) hiddenPropDepth = propDepth + 1;
                if (TreasureSpace is { } beach && System.Numerics.Vector2.Distance(p * .01f, beach) < footprintRadius * scale + .48f)
                    hiddenPropDepth = propDepth + 1;
            }
            Transform *= new Transform3D(Basis.Identity.Scaled(Vector3.One * scale), at);
            propDepth++;
            return old;
        }
        public void EndProp(Transform3D old)
        {
            if (hiddenPropDepth == propDepth) hiddenPropDepth = 0;
            Transform = old; propDepth--;
        }
        private Vector3 Placed(Vector3 local)
        {
            var p = Transform * local;
            if (Footprint == null || propDepth > 0) return p;
            var shore = Footprint.PlaceOnLand(new(p.X * 90, p.Z * 90));
            return new(shore.X * .01f, p.Y, shore.Y * .01f);
        }

        private SurfaceTool Surface(string key)
        {
            if (surfaces.TryGetValue(key, out var found)) return found;
            var surface = new SurfaceTool(); surface.Begin(Mesh.PrimitiveType.Triangles); surfaces.Add(key, surface); return surface;
        }
        public void Triangle(Vector3 a, Vector3 b, Vector3 c, Color ca, Color cb, Color cc, Vector3 na, Vector3 nb, Vector3 nc, string key = "matte",
            Vector2? ua = null, Vector2? ub = null, Vector2? uc = null)
        {
            if (hiddenPropDepth > 0) return;
            Vector3 cross = (b - a).Cross(c - a);
            if (cross.LengthSquared() < 1e-14f) return;
            if (cross.Dot(na + nb + nc) < 0) { (b, c) = (c, b); (nb, nc) = (nc, nb); (cb, cc) = (cc, cb); (ub, uc) = (uc, ub); }
            var s = Surface(key);
            var placedA = Placed(a); var placedB = Placed(b); var placedC = Placed(c);
            var face = (placedB - placedA).Cross(placedC - placedA).Normalized();
            void Vertex(Vector3 p, Vector3 placed, Color color, Vector3 normal, Vector2? uv)
            {
                s.SetColor(color); s.SetUV(uv ?? new(p.X, p.Z));
                s.SetNormal(Footprint == null || propDepth > 0 ? (Transform.Basis * normal).Normalized() : face);
                s.AddVertex(placed);
            }
            // Godot front faces use clockwise winding. Our geometric normals are explicit.
            Vertex(a, placedA, ca, na, ua); Vertex(c, placedC, cc, nc, uc); Vertex(b, placedB, cb, nb, ub);
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
            // Four divisions preserve broad faces between rounded corners.
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
            var rng=new SeedRandom(seed); const int sides=7;
            var rings=new Vector3[4][];
            float[] heights=[-.48f,-.05f,.25f,.49f]; float[] widths=[.52f,.49f,.43f,.32f];
            float phase=rng.Range(0,1);
            var offsets=Enumerable.Range(0,sides).Select(_=>rng.Range(.80f,1.18f)).ToArray();
            var angles=Enumerable.Range(0,sides).Select(i=>phase+i*Mathf.Tau/sides+rng.Range(-.13f,.13f)).ToArray();
            var shoulders=Enumerable.Range(0,sides).Select(_=>rng.Range(-.15f,.22f)).ToArray();
            var caps=Enumerable.Range(0,sides).Select(_=>rng.Range(.82f,1.15f)).ToArray();
            bool foliage=color.G>color.R*1.1f&&color.G>color.B*1.1f;
            for(int j=0;j<4;j++)
            {
                rings[j]=new Vector3[sides];
                for(int i=0;i<sides;i++)
                {
                    float a=angles[i], radius=widths[j]*offsets[i]*(j>=2?caps[i]:1);
                    rings[j][i]=p+new Vector3(Mathf.Cos(a)*radius+j*.027f,heights[j]+(j==3?Mathf.Cos(a)*.08f:j==1?shoulders[i]*.65f:j==2?shoulders[i]*.4f:0),Mathf.Sin(a)*radius-j*.020f)*size;
                }
            }
            for(int j=0;j<3;j++) for(int i=0;i<sides;i++)
            {
                int n=(i+1)%sides;
                var shade=color.Lightened((i%3)*.038f + (j==2?.04f:0));
                Face(rings[j][n],rings[j][i],rings[j+1][i],shade);
                Face(rings[j][n],rings[j+1][i],rings[j+1][n],foliage?shade:shade.Darkened((i+j)%3*.065f));
            }
            var center=rings[3].Aggregate(Vector3.Zero,(sum,v)=>sum+v)/sides;
            Color cap=foliage?color.Lightened(.12f):color.Lerp(new Color("d9cfac"),.46f);
            for(int i=0;i<sides;i++) Face(center,rings[3][(i+1)%sides],rings[3][i],cap.Lightened(i%3*.025f));
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
        public Node3D Finish(string name)
        {
            var root = new Node3D { Name = name };
            foreach (var (key, surface) in surfaces)
            {
                if (!Materials.TryGetValue(key, out var material))
                {
                    material = key switch
                    {
                        "shelf" => new ShaderMaterial { Shader = GD.Load<Shader>("res://source/presentation/EnvironmentShallows.gdshader") },
                        "lantern" => new StandardMaterial3D { VertexColorUseAsAlbedo = true, ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded, CullMode = BaseMaterial3D.CullModeEnum.Disabled },
                        "ground" => new ShaderMaterial { Shader = GD.Load<Shader>("res://source/presentation/island-ground.gdshader") },
                        _ => DioramaSurface.Material
                    };
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
