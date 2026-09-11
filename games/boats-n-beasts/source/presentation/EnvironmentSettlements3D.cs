using Godot;
using BoatsNBeasts.Core;

namespace BoatsNBeasts;

public static partial class EnvironmentArt3D
{
    // Independent of coastline selection: retain the original interiors on most islands.
    private static int SettlementKind(float r, uint seed) => new SeedRandom(seed ^ 0xa43fu).Index(8) switch
    {
        0 when r >= 2.5f => 0,
        1 when r >= 1.4f => 1,
        _ => -1
    };

    public static string IslandScenery(float radius, uint seed) => SettlementKind(radius * .01f, seed) switch
    {
        0 => "Prison", 1 => "Watchtower", _ => (seed % 3) switch { 0 => "Ruins", 1 => "Grove", _ => "Cliffs" }
    };

    private static bool SettlementInterior(Sculptor art, float r, uint seed)
    {
        int kind = SettlementKind(r, seed);
        if (kind < 0 || art.Footprint == null) return false;
        // Find room using the actual coast, not a shape-specific placement rule.
        Vector3 anchor = Vector3.Zero;
        float best = 0;
        for (int i = 0; i < 49; i++)
        {
            float angle = i * Mathf.Tau / 16;
            float reach = i == 0 ? 0 : (.20f + (i - 1) / 16 * .20f) * r;
            var candidate = new Vector2(MathF.Cos(angle), MathF.Sin(angle)) * reach;
            var placed = art.Footprint.PlaceOnLand(new(candidate.X * 100, candidate.Y * 100)) * .01f;
            float room = InlandClearance(art.Footprint, new(placed.X, placed.Y)) - art.BeachReserve;
            if (art.TreasureSpace is { } treasure) room = MathF.Min(room, System.Numerics.Vector2.Distance(placed, treasure) - .48f);
            if (room <= best) continue;
            best = room; anchor = new(candidate.X, .16f, candidate.Y);
        }
        // If the island cannot carry a readable landmark, retain its natural interior.
        if (best < .50f) return false;
        // The prison radius includes the projecting gatehouse and entrance steps.
        float footprint = kind == 0 ? 1.56f : .82f;
        float scale = MathF.Min(MathF.Min(r * (kind == 0 ? .72f : .48f), 3.0f), best / (footprint * art.HeightScale));
        var old = art.PlaceProp(anchor, footprint * scale);
        art.Transform *= new Transform3D(Basis.FromEuler(new(0, kind == 0 ? -.32f : -.55f, 0)).Scaled(Vector3.One * scale), Vector3.Zero);
        var building = art.Transform;
        if (kind == 0) Prison(art); else Watchtower(art);
        art.EndProp(old);
        float size = building.Basis.X.Length();
        art.LandmarkSpace = (new(building.Origin.X, building.Origin.Z), footprint * size);
        if (kind == 0) PrisonJetty(art, building);

        var rng = new SeedRandom(seed + 117);
        int groups = Math.Clamp((int)(r * 3), 6, 16);
        for (int i = 0; i < groups; i++)
        {
            float angle = i * 2.39996f + rng.Range(-.18f, .18f);
            float reach = r * (i % 2 == 0 ? .55f : .72f);
            var at = new Vector3(MathF.Cos(angle) * reach, .14f, MathF.Sin(angle) * reach);
            Rock(art, at, new(r * .27f, r * (i % 3 == 0 ? .85f : .25f), r * .25f), rng.Next(), moss: true);
            if (i % 2 == 0) Palm(art, at + new Vector3(-r * .07f, 0, -r * .06f), r * .46f, rng.Next());
        }
        return true;
    }

    private const float PrisonGateOffset = .40f;

    private static void Prison(Sculptor art)
    {
        // Muted slate and a lighter courtyard separate the towers from the walls.
        Color stone = new("77828c"), trim = new("a0a7ad"), iron = new("343b45");
        var building = art.Transform;
        // A low courtyard disk and an open, sixteen-sided wall keep the circular
        // silhouette readable without a solid cylinder filling the courtyard.
        art.Tube(new(0, .015f, 0), new(0, .10f, 0), 1.35f, 1.35f, new("96998f"), 16);
        WallBand(1.32f, 1.15f, .10f, .70f, stone);
        WallBand(1.34f, 1.13f, .70f, .77f, trim);
        for (int i = 0; i < 28; i++)
        {
            float angle = Mathf.Pi / 8 + (i + .5f) * Mathf.Pi / 16;
            art.Transform = building * new Transform3D(Basis.FromEuler(new(0, angle, 0)),
                new(Mathf.Sin(angle) * 1.235f, .82f, Mathf.Cos(angle) * 1.235f));
            art.RoundedBox(Vector3.Zero, new(.14f, .15f, .19f), .012f, trim);
        }
        art.Transform = building;
        // Three towers are enough to identify the keep; omit the tiny roof turrets
        // and brick seams that disappear at the normal voyage camera distance.
        PrisonTower(art, new(0, 0, -.40f), .34f, 1.48f, stone, trim);
        for (int side = -1; side <= 1; side += 2)
            PrisonTower(art, new(side * .73f, 0, .04f), .18f, 1.04f, stone, trim);

        // The gatehouse closes the front gap in the ring and projects toward the dock.
        var gate = building * new Transform3D(Basis.Identity, new(0, 0, PrisonGateOffset));
        art.Transform = gate;
        for (int side = -1; side <= 1; side += 2)
        {
            art.RoundedBox(new(side * .405f, .44f, .835f), new(.25f, .72f, .28f), .018f, stone);
            art.RoundedBox(new(side * .405f, .13f, .84f), new(.28f, .14f, .30f), .012f, trim);
            art.RoundedBox(new(side * .405f, .84f, .84f), new(.29f, .10f, .32f), .014f, trim);
            NavyBanner(art, new(side * .405f, .54f, .988f), .16f, .43f);
        }
        art.RoundedBox(new(0, .855f, .82f), new(1.02f, .15f, .26f), .012f, stone);
        for (int i = -2; i <= 2; i++)
            art.RoundedBox(new(i * .21f, .965f, .82f), new(.12f, .13f, .24f), .010f, trim);
        const float gateBase = .10f, gateSpring = .49f, gateRadius = .26f;
        Arch(art, new(0, gateBase, .86f), gateRadius * 2, gateSpring + gateRadius - gateBase, .065f, iron.Darkened(.35f), trim);
        for (int i = 0; i <= 8; i++)
        {
            float angle = i * Mathf.Pi / 8;
            art.Transform = gate * new Transform3D(Basis.FromEuler(new(0, 0, angle - Mathf.Pi / 2)),
                new(Mathf.Cos(angle) * .30f, gateSpring + Mathf.Sin(angle) * .30f, .93f));
            art.RoundedBox(Vector3.Zero, new(.12f, .09f, .13f), .009f, trim);
        }
        art.Transform = gate;
        for (int side = -1; side <= 1; side += 2)
            art.RoundedBox(new(side * .30f, .295f, .93f), new(.09f, .39f, .13f), .009f, trim);
        for (int i = -3; i <= 3; i++)
        {
            float x = i * .068f;
            float top = gateSpring + Mathf.Sqrt(gateRadius * gateRadius - x * x) - .025f;
            art.Tube(new(x, gateBase, .91f), new(x, top, .91f), .013f, .013f, iron, 5);
        }
        foreach (float y in new[] { .27f, .48f })
            art.RoundedBox(new(0, y, .925f), new(.51f, .027f, .027f), .003f, iron);
        for (int i = 0; i < 2; i++)
            art.RoundedBox(new(0, .10f - i * .035f, .99f + i * .07f), new(.55f, .06f, .09f), .010f, trim);
        art.Transform = building;

        void WallBand(float outer, float inner, float bottom, float top, Color color)
        {
            // Leave forty-five degrees open, keeping the gate width independent of the larger yard.
            for (int i = 1; i < 15; i++)
            {
                float a = i * Mathf.Tau / 16, b = (i + 1) * Mathf.Tau / 16;
                Vector3 Point(float angle, float radius, float y) => new(Mathf.Sin(angle) * radius, y, Mathf.Cos(angle) * radius);
                Vector3 obA = Point(a, outer, bottom), obB = Point(b, outer, bottom);
                Vector3 otA = Point(a, outer, top), otB = Point(b, outer, top);
                Vector3 ibA = Point(a, inner, bottom), ibB = Point(b, inner, bottom);
                Vector3 itA = Point(a, inner, top), itB = Point(b, inner, top);
                art.Quad(obA, obB, otB, otA, color);
                art.Quad(ibB, ibA, itA, itB, color.Darkened(.08f));
                art.Quad(otA, otB, itB, itA, color.Lightened(.05f));
                if (i == 1) art.Quad(ibA, obA, otA, itA, color);
                if (i == 14) art.Quad(obB, ibB, itB, otB, color);
            }
        }
    }

    private static void PrisonTower(Sculptor art, Vector3 at, float radius, float height, Color stone, Color trim)
    {
        var building = art.Transform;
        art.Transform = building * new Transform3D(Basis.Identity, at);
        art.Tube(new(0, .10f, 0), new(0, height, 0), radius, radius * .95f, stone, 12);
        art.Tube(new(0, height - .07f, 0), new(0, height + .035f, 0), radius * 1.09f, radius * 1.09f, trim, 12);
        // Explicit sloped face normals make the roof read as a cone in the
        // elevated camera; Tube's radial normals are intended for shafts.
        for (int i = 0; i < 12; i++)
        {
            float a = i * Mathf.Tau / 12, b = (i + 1) * Mathf.Tau / 12;
            art.Face(new(Mathf.Sin(a) * radius, height + .035f, Mathf.Cos(a) * radius),
                new(Mathf.Sin(b) * radius, height + .035f, Mathf.Cos(b) * radius),
                new(0, height + radius * 1.25f, 0), new("89565b"));
        }
        if (radius > .3f)
            for (int i = 0; i < 8; i++)
            {
                float angle = i * Mathf.Tau / 8;
                art.Transform = building * new Transform3D(Basis.FromEuler(new(0, angle, 0)), at);
                art.RoundedBox(new(0, height + .07f, radius), new(.10f, .12f, .09f), .008f, trim);
            }
        // Sparse dark slits sit against polygon faces; no textures or tiny masonry.
        for (int i = 0; i < 6; i++)
        {
            float angle = i * Mathf.Tau / 6;
            art.Transform = building * new Transform3D(Basis.FromEuler(new(0, angle, 0)), at);
            art.RoundedBox(new(0, height - .24f, radius * .955f), new(radius * .22f, .16f, .025f), .004f, new("202731"));
        }
        art.Transform = building;
    }

    private static void Watchtower(Sculptor art)
    {
        Color wood = new("87613b"), cut = new("b18a52"), dark = new("60472f"), roof = new("b47b41");
        const float deck = 2.25f, eaves = 2.90f;
        // Tall open legs, horizontal ties and an open-sided lookout.
        // All access details are deliberately omitted from this decorative landmark.
        for (int x = -1; x <= 1; x += 2) for (int z = -1; z <= 1; z += 2)
        {
            var foot = new Vector3(x * .44f, 0, z * .44f);
            var landing = new Vector3(x * .28f, deck, z * .28f);
            art.RoundedBox(foot + new Vector3(0, .05f, 0), new(.23f, .10f, .23f), .025f, Stone);
            art.Tube(foot, landing, .068f, .050f, wood, 5);
            art.Tube(landing, new(x * .28f, eaves, z * .28f), .050f, .042f, wood, 5);
        }
        // Keep the base open: horizontal collars only, with no diagonal braces.
        for (int side = -1; side <= 1; side += 2)
        {
            foreach (float y in new[] { deck * .20f, deck * .48f })
            {
                float half = Mathf.Lerp(.44f, .28f, y / deck);
                art.RoundedBox(new(0, y, side * half), new(half * 2, .075f, .065f), .009f, cut);
                art.RoundedBox(new(side * half, y, 0), new(.065f, .075f, half * 2), .009f, wood);
            }
            art.RoundedBox(new(side * .285f, deck - .09f, 0), new(.095f, .13f, .83f), .012f, dark);
        }
        for (int i = 0; i < 7; i++)
            art.RoundedBox(new(0, deck, -.345f + i * .115f), new(.83f, .075f, .11f), .009f, cut.Lightened(i % 3 * .025f));
        for (int side = -1; side <= 1; side += 2)
        {
            art.RoundedBox(new(side * .315f, deck + .12f, 0), new(.065f, .07f, .70f), .01f, cut);
            art.RoundedBox(new(0, deck + .12f, side * .315f), new(.70f, .07f, .065f), .01f, cut);
        }
        HipRoof(art, new(.49f, eaves, .49f), 3.32f, 0, roof);
        var tower = art.Transform;
        art.Transform = tower * new Transform3D(Basis.Identity, new(0, deck + .10f, .43f));
        WatchtowerBanner(art, .37f, 1.10f);
        art.Transform = tower * new Transform3D(Basis.FromEuler(new(0, Mathf.Pi / 2, 0)), new(.44f, eaves - .08f, -.04f));
        WatchtowerBanner(art, .34f, 1.32f);
        art.Transform = tower;
    }

    private static void WatchtowerBanner(Sculptor art, float width, float height)
    {
        Color navy = new("34406f"), ivory = new("eee2b6");
        float half = width * .5f;
        // Long cloth with a notched hem, hanging from a visible timber crossbar.
        art.Tube(new(-half - .025f, .025f, 0), new(half + .025f, .025f, 0), .021f, .021f, new("87613b"), 5);
        Vector3 left = new(-half, -height * .82f, .015f), right = new(half, -height * .82f, .015f);
        art.Quad(new(-half, 0, 0), left, right, new(half, 0, 0), navy);
        var notch = new Vector3(0, -height * .84f, .015f);
        art.Face(left, notch, right, navy);
        art.Face(left, new(-half, -height, .025f), notch, navy);
        art.Face(notch, new(half, -height, .025f), right, navy);
        var skull = new Vector3(0, -height * .38f, .034f);
        art.Ellipsoid(skull, new(width * .27f, width * .30f, .023f), ivory, 8, 5);
        art.RoundedBox(skull + new Vector3(0, -width * .25f, .008f), new(width * .31f, width * .24f, .025f), .006f, ivory);
        for (int side = -1; side <= 1; side += 2)
            art.Ellipsoid(skull + new Vector3(side * width * .105f, .005f, .023f), new(width * .070f, width * .09f, .005f), navy, 6, 4);
        for (int i = -1; i <= 1; i++)
            art.RoundedBox(skull + new Vector3(i * width * .09f, -width * .31f, .024f), new(.008f, width * .13f, .008f), .001f, navy);
    }

    private static void HipRoof(Sculptor art, Vector3 eaves, float peak, float ridge, Color color)
    {
        Vector3 a = new(-eaves.X, eaves.Y, eaves.Z), b = new(eaves.X, eaves.Y, eaves.Z);
        Vector3 c = new(eaves.X, eaves.Y, -eaves.Z), d = new(-eaves.X, eaves.Y, -eaves.Z);
        Vector3 left = new(-ridge, peak, 0), right = new(ridge, peak, 0);
        art.Quad(a, b, right, left, color);
        art.Face(b, c, right, color.Lightened(.10f));
        art.Quad(c, d, left, right, color.Darkened(.06f));
        art.Face(d, a, left, color.Lightened(.04f));
        Vector3[] edge = [a, b, c, d];
        for (int i = 0; i < 4; i++) art.Tube(edge[i], edge[(i + 1) % 4], .025f, .025f, color.Darkened(.17f), 4);
        if (ridge > 0) art.Tube(left, right, .03f, .03f, color.Lightened(.09f), 5);
    }

    private static void NavyBanner(Sculptor art, Vector3 at, float width, float height)
    {
        art.RoundedBox(at, new(width, height, .024f), .006f, new("34406f"));
        // A simple ivory anchor reads at gameplay scale without a texture.
        float s = width;
        Color ivory = new("eee2b6");
        art.Tube(at + new Vector3(0, s * .32f, .019f), at + new Vector3(0, -s * .27f, .019f), s * .05f, s * .05f, ivory, 5);
        art.Tube(at + new Vector3(-s * .20f, s * .16f, .019f), at + new Vector3(s * .20f, s * .16f, .019f), s * .045f, s * .045f, ivory, 5);
        for (int side = -1; side <= 1; side += 2)
            art.Tube(at + new Vector3(0, -s * .27f, .019f), at + new Vector3(side * s * .28f, -s * .05f, .019f), s * .05f, s * .05f, ivory, 5);
    }

    private static void PrisonJetty(Sculptor art, Transform3D building)
    {
        float scale = building.Basis.X.Length(), halfWidth = scale * .29f;
        var start = building * new Vector3(0, 0, 1.08f + PrisonGateOffset);
        var basis = building.Basis.Orthonormalized();
        var direction = new Vector2(basis.Z.X, basis.Z.Z);
        float length = 0;
        // Stop within the dry coast: decorative timber never creates an invisible
        // obstacle in navigable water or requires a separate collision footprint.
        for (int i = 1; i <= 128; i++)
        {
            float next = i * .06f;
            var center = new Vector2(start.X, start.Z) + direction * next;
            if (InlandClearance(art.Footprint!, center) < halfWidth + .02f) break;
            if (art.TreasureSpace is { } treasure && center.DistanceTo(new(treasure.X, treasure.Y)) < halfWidth + .48f) break;
            length = next;
        }
        if (length < .12f) return;
        // Enter a fitted prop so mesh vertices retain their world-space positions.
        var old = art.BeginWorldProp();
        art.Transform = new Transform3D(basis, new(start.X, .25f, start.Z));
        int planks = Math.Max(2, (int)MathF.Ceiling(length / (.10f * scale)));
        for (int i = 0; i <= planks; i++)
            art.RoundedBox(new(0, 0, length * i / planks), new(halfWidth * 2, .065f, length / planks * .94f), .012f, new Color("795e49").Lightened(i % 3 * .025f));
        for (int side = -1; side <= 1; side += 2) for (int i = 0; i < 3; i++)
        {
            var foot = new Vector3(side * halfWidth * .88f, -.23f, length * i / 2);
            art.Tube(foot, foot + new Vector3(0, .27f + .16f * scale, 0), scale * .045f, scale * .040f, new("604a38"), 7);
        }
        art.EndProp(old);
        art.JettySpace = (new(start.X, start.Z), new Vector2(start.X, start.Z) + direction * length, halfWidth);
    }
}
