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
        float footprint = kind == 0 ? 1.0f : .82f;
        float scale = MathF.Min(MathF.Min(r * (kind == 0 ? .60f : .48f), 3.0f), best / (footprint * art.HeightScale));
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

    private static void Prison(Sculptor art)
    {
        Color plaster = new("d3ceb2"), trim = new("eee0b6"), iron = new("34474e"), roof = new("b47b41");
        art.RoundedBox(new(0, .05f, 0), new(1.40f, .14f, 1.06f), .035f, new("a29f89"));
        art.RoundedBox(new(0, .57f, -.025f), new(1.28f, 1.04f, .91f), .045f, plaster);
        art.RoundedBox(new(0, 1.09f, -.025f), new(1.38f, .12f, 1.01f), .025f, trim);
        HipRoof(art, new(.74f, 1.16f, .53f), 1.46f, .28f, roof);
        // Projecting gate pillars frame a tall entrance instead of a flat box face.
        for (int side = -1; side <= 1; side += 2)
        {
            art.RoundedBox(new(side * .55f, .57f, .46f), new(.23f, 1.10f, .28f), .025f, plaster.Darkened(.05f));
            art.RoundedBox(new(side * .55f, 1.15f, .46f), new(.30f, .12f, .35f), .022f, trim);
            art.RoundedBox(new(side * .55f, .12f, .46f), new(.28f, .22f, .34f), .02f, new("aaa58a"));
            if (side > 0) NavyBanner(art, new(side * .55f, .79f, .614f), .18f, .48f);
        }
        // One raised octagonal corner breaks the roofline and identifies a fortified lockup.
        var turret = new Vector3(-.53f, 0, .40f);
        art.Tube(turret + new Vector3(0, .08f, 0), turret + new Vector3(0, 1.45f, 0), .235f, .225f, plaster, 8);
        art.Tube(turret + new Vector3(0, 1.40f, 0), turret + new Vector3(0, 1.52f, 0), .265f, .265f, trim, 8);
        art.Tube(turret + new Vector3(0, 1.53f, 0), turret + new Vector3(0, 1.94f, 0), .29f, .015f, roof, 8);
        art.RoundedBox(turret + new Vector3(0, 1.24f, .225f), new(.095f, .19f, .018f), .006f, new("24373b"));
        NavyBanner(art, turret + new Vector3(0, .80f, .24f), .18f, .43f);
        const float gateBase = .11f, gateSpring = .69f, gateRadius = .29f;
        Arch(art, new(0, gateBase, .449f), gateRadius * 2, gateSpring + gateRadius - gateBase, .065f, new("24373b"), trim);
        // Broad voussoirs give the arch depth and remain readable at game scale.
        var wall = art.Transform;
        for (int i = 0; i <= 8; i++)
        {
            float a = i * Mathf.Pi / 8;
            art.Transform = wall * new Transform3D(Basis.FromEuler(new(0, 0, a - Mathf.Pi / 2)),
                new(MathF.Cos(a) * .35f, gateSpring + MathF.Sin(a) * .35f, .50f));
            art.RoundedBox(Vector3.Zero, new(.14f, .13f, .13f), .012f, trim.Darkened(i % 3 * .025f));
        }
        art.Transform = wall;
        for (int side = -1; side <= 1; side += 2)
            art.RoundedBox(new(side * .35f, .40f, .50f), new(.12f, .59f, .13f), .014f, trim);
        for (int i = -3; i <= 3; i++)
        {
            float x = i * .077f;
            float top = gateSpring + MathF.Sqrt(gateRadius * gateRadius - x * x) - .035f;
            art.Tube(new(x, gateBase, .495f), new(x, top, .495f), .016f, .016f, iron, 5);
        }
        foreach (float y in new[] { .32f, .62f })
            art.RoundedBox(new(0, y, .514f), new(.55f, .029f, .028f), .004f, iron);
        art.RoundedBox(new(.06f, .48f, .525f), new(.085f, .12f, .04f), .008f, new("79663d"));
        // A barred side window makes the angled view read as a lockup.
        art.Transform = wall * new Transform3D(Basis.FromEuler(new(0, Mathf.Pi / 2, 0)), new(.65f, .68f, -.03f));
        art.RoundedBox(Vector3.Zero, new(.30f, .35f, .045f), .015f, trim);
        art.RoundedBox(new(0, 0, .027f), new(.23f, .28f, .025f), .008f, new("24373b"));
        for (int i = -1; i <= 1; i++) art.Tube(new(i * .065f, -.13f, .048f), new(i * .065f, .13f, .048f), .012f, .012f, iron, 5);
        art.Transform = wall;
        for (int i = 0; i < 3; i++)
            art.RoundedBox(new(0, .10f - i * .023f, .57f + i * .10f), new(.60f + i * .055f, .07f, .13f), .014f, trim);
        Crate(art, new(-.72f, .11f, .35f), .19f);
        Crate(art, new(.73f, .095f, .37f), .16f);
    }

    private static void Watchtower(Sculptor art)
    {
        Color wood = new("87613b"), cut = new("b18a52"), dark = new("60472f"), roof = new("b47b41");
        const float deck = 1.64f, eaves = 2.23f;
        // Reference silhouette: long open legs, low ties and an open-sided lookout.
        // All access details are deliberately omitted from this decorative landmark.
        for (int x = -1; x <= 1; x += 2) for (int z = -1; z <= 1; z += 2)
        {
            var foot = new Vector3(x * .44f, 0, z * .44f);
            var landing = new Vector3(x * .28f, deck, z * .28f);
            art.RoundedBox(foot + new Vector3(0, .05f, 0), new(.23f, .10f, .23f), .025f, Stone);
            art.Tube(foot, landing, .068f, .050f, wood, 5);
            art.Tube(landing, new(x * .28f, eaves, z * .28f), .050f, .042f, wood, 5);
        }
        // One diagonal per lower face, between two horizontal ties; never an X.
        for (int side = -1; side <= 1; side += 2)
        {
            foreach (float y in new[] { .34f, .80f })
            {
                float half = Mathf.Lerp(.44f, .28f, y / deck);
                art.RoundedBox(new(0, y, side * half), new(half * 2, .075f, .065f), .009f, cut);
                art.RoundedBox(new(side * half, y, 0), new(.065f, .075f, half * 2), .009f, wood);
            }
            art.Tube(new(-.407f, .36f, side * .407f), new(.363f, .78f, side * .363f), .034f, .034f, wood, 4);
            art.Tube(new(side * .407f, .36f, -.407f), new(side * .363f, .78f, .363f), .034f, .034f, dark, 4);
            art.RoundedBox(new(side * .285f, deck - .09f, 0), new(.095f, .13f, .83f), .012f, dark);
        }
        for (int i = 0; i < 7; i++)
            art.RoundedBox(new(0, deck, -.345f + i * .115f), new(.83f, .075f, .11f), .009f, cut.Lightened(i % 3 * .025f));
        for (int side = -1; side <= 1; side += 2)
        {
            art.RoundedBox(new(side * .315f, deck + .12f, 0), new(.065f, .07f, .70f), .01f, cut);
            art.RoundedBox(new(0, deck + .12f, side * .315f), new(.70f, .07f, .065f), .01f, cut);
        }
        HipRoof(art, new(.49f, eaves, .49f), 2.65f, 0, roof);
        var tower = art.Transform;
        art.Transform = tower * new Transform3D(Basis.Identity, new(0, deck + .10f, .43f));
        WatchtowerBanner(art, .37f, .83f);
        art.Transform = tower * new Transform3D(Basis.FromEuler(new(0, Mathf.Pi / 2, 0)), new(.44f, eaves - .08f, -.04f));
        WatchtowerBanner(art, .34f, 1.04f);
        art.Transform = tower;
    }

    private static void WatchtowerBanner(Sculptor art, float width, float height)
    {
        Color navy = new("304967"), ivory = new("eee2b6");
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
        art.RoundedBox(at, new(width, height, .024f), .006f, new("304967"));
        // A simple ivory anchor reads at gameplay scale without a texture.
        float s = width;
        Color ivory = new("eee2b6");
        art.Tube(at + new Vector3(0, s * .32f, .019f), at + new Vector3(0, -s * .27f, .019f), s * .05f, s * .05f, ivory, 5);
        art.Tube(at + new Vector3(-s * .20f, s * .16f, .019f), at + new Vector3(s * .20f, s * .16f, .019f), s * .045f, s * .045f, ivory, 5);
        for (int side = -1; side <= 1; side += 2)
            art.Tube(at + new Vector3(0, -s * .27f, .019f), at + new Vector3(side * s * .28f, -s * .05f, .019f), s * .05f, s * .05f, ivory, 5);
    }

    private static void Crate(Sculptor art, Vector3 at, float size)
    {
        art.RoundedBox(at, Vector3.One * size, .012f, new("987347"));
        art.Tube(at + new Vector3(-size * .40f, -size * .40f, size * .51f), at + new Vector3(size * .40f, size * .40f, size * .51f), size * .07f, size * .07f, new("634a30"), 4);
    }

    private static void PrisonJetty(Sculptor art, Transform3D building)
    {
        float scale = building.Basis.X.Length(), halfWidth = scale * .29f;
        var start = building * new Vector3(0, 0, .82f);
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
            art.RoundedBox(new(0, 0, length * i / planks), new(halfWidth * 2, .065f, length / planks * .94f), .012f, new Color("a17a49").Lightened(i % 3 * .025f));
        for (int side = -1; side <= 1; side += 2) for (int i = 0; i < 3; i++)
        {
            var foot = new Vector3(side * halfWidth * .88f, -.23f, length * i / 2);
            art.Tube(foot, foot + new Vector3(0, .27f + .16f * scale, 0), scale * .045f, scale * .040f, new("795636"), 7);
        }
        art.EndProp(old);
        art.JettySpace = (new(start.X, start.Z), new Vector2(start.X, start.Z) + direction * length, halfWidth);
    }
}
