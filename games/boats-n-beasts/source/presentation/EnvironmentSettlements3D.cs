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
        float footprint = kind == 0 ? 1.0f : .78f;
        float scale = MathF.Min(MathF.Min(r * (kind == 0 ? .60f : .48f), 3.0f), best / (footprint * art.HeightScale));
        var old = art.PlaceProp(anchor, footprint * scale);
        art.Transform *= new Transform3D(Basis.Identity.Scaled(Vector3.One * scale), Vector3.Zero);
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
        Color plaster = new("d3ceb2"), trim = new("eee0b6"), wood = new("805b38"), iron = new("34474e");
        art.RoundedBox(new(0, .05f, 0), new(1.36f, .12f, 1.02f), .03f, new("a29f89"));
        art.RoundedBox(new(0, .43f, 0), new(1.22f, .78f, .86f), .045f, plaster);
        art.RoundedBox(new(0, .85f, 0), new(1.35f, .15f, .98f), .025f, trim);
        // A warm flat roof and four low parapets leave a strong prison silhouette.
        art.RoundedBox(new(0, .94f, 0), new(1.14f, .07f, .76f), .015f, wood);
        for (int side = -1; side <= 1; side += 2)
        {
            art.RoundedBox(new(side * .62f, 1.01f, 0), new(.12f, .22f, .94f), .018f, plaster);
            art.RoundedBox(new(0, 1.01f, side * .41f), new(1.25f, .22f, .12f), .018f, plaster);
            art.RoundedBox(new(side * .56f, .40f, .45f), new(.14f, .79f, .13f), .02f, trim);
            NavyBanner(art, new(side * .43f, .61f, .53f), .23f, .43f);
        }
        Arch(art, new(0, .10f, .451f), .42f, .61f, .045f, new("25363a"), trim);
        for (int i = -2; i <= 2; i++)
            art.Tube(new(i * .071f, .11f, .49f), new(i * .071f, .62f - MathF.Abs(i) * .025f, .49f), .015f, .015f, iron, 5);
        art.RoundedBox(new(0, .31f, .505f), new(.39f, .025f, .026f), .004f, iron);
        for (int i = 0; i < 3; i++)
            art.RoundedBox(new(0, .07f - i * .025f, .53f + i * .10f), new(.51f + i * .07f, .08f, .13f), .01f, trim);
        Crate(art, new(-.69f, .10f, .44f), .19f);
        Crate(art, new(.69f, .10f, .39f), .16f);
    }

    private static void Watchtower(Sculptor art)
    {
        Color wood = new("87613b"), cut = new("b18a52"), dark = new("60472f"), roof = new("bb8040");
        for (int x = -1; x <= 1; x += 2) for (int z = -1; z <= 1; z += 2)
        {
            var foot = new Vector3(x * .43f, 0, z * .43f);
            art.RoundedBox(foot + new Vector3(0, .05f, 0), new(.24f, .10f, .24f), .025f, Stone);
            art.Tube(foot, new(x * .28f, 1.99f, z * .28f), .065f, .047f, wood, 5);
        }
        for (int side = -1; side <= 1; side += 2)
        {
            art.Tube(new(-.40f, .19f, side * .39f), new(.30f, 1.39f, side * .30f), .035f, .035f, cut, 4);
            art.Tube(new(.40f, .19f, side * .39f), new(-.30f, 1.39f, side * .30f), .035f, .035f, cut, 4);
            art.Tube(new(side * .39f, .19f, -.40f), new(side * .30f, 1.39f, .30f), .035f, .035f, dark, 4);
        }
        art.RoundedBox(new(0, 1.43f, 0), new(.94f, .13f, .94f), .018f, cut);
        for (int side = -1; side <= 1; side += 2)
        {
            art.RoundedBox(new(side * .42f, 1.64f, 0), new(.055f, .29f, .86f), .012f, wood);
            art.RoundedBox(new(0, 1.64f, side * .42f), new(.86f, .29f, .055f), .012f, wood);
        }
        Vector3 peak = new(0, 2.33f, 0);
        Vector3[] corners = [new(-.55f, 1.95f, -.55f), new(.55f, 1.95f, -.55f), new(.55f, 1.95f, .55f), new(-.55f, 1.95f, .55f)];
        for (int i = 0; i < 4; i++) art.Face(corners[i], peak, corners[(i + 1) % 4], roof.Lightened(i * .035f));
        for (int side = -1; side <= 1; side += 2)
            art.Tube(new(side * .12f, .08f, .49f), new(side * .12f, 1.43f, .35f), .022f, .022f, dark, 5);
        for (int i = 0; i < 8; i++)
            art.Tube(new(-.14f, .15f + i * .16f, .48f - i * .016f), new(.14f, .15f + i * .16f, .48f - i * .016f), .024f, .024f, cut, 5);
        NavyBanner(art, new(0, 1.65f, .465f), .32f, .46f);
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
        var start = building * new Vector3(0, 0, .76f);
        float length = 0;
        // Stop within the dry coast: decorative timber never creates an invisible
        // obstacle in navigable water or requires a separate collision footprint.
        for (int i = 1; i <= 128; i++)
        {
            float next = i * .06f;
            var center = new Vector2(start.X, start.Z + next);
            if (InlandClearance(art.Footprint!, center) < halfWidth + .02f) break;
            if (art.TreasureSpace is { } treasure && center.DistanceTo(new(treasure.X, treasure.Y)) < halfWidth + .48f) break;
            length = next;
        }
        if (length < .12f) return;
        // Enter a fitted prop so mesh vertices retain their world-space positions.
        var old = art.BeginWorldProp();
        int planks = Math.Max(2, (int)MathF.Ceiling(length / (.10f * scale)));
        for (int i = 0; i <= planks; i++)
            art.RoundedBox(new(start.X, .25f, start.Z + length * i / planks), new(halfWidth * 2, .065f, length / planks * .94f), .012f, new Color("a17a49").Lightened(i % 3 * .025f));
        for (int side = -1; side <= 1; side += 2) for (int i = 0; i < 3; i++)
        {
            var foot = new Vector3(start.X + side * halfWidth * .88f, .02f, start.Z + length * i / 2);
            art.Tube(foot, foot + new Vector3(0, .27f + .16f * scale, 0), scale * .045f, scale * .040f, new("795636"), 7);
        }
        art.EndProp(old);
        art.JettySpace = (new(start.X, start.Z), new(start.X, start.Z + length), halfWidth);
    }
}
