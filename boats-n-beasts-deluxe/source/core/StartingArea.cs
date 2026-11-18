using System.Numerics;
namespace BoatsNBeasts.Core;

// The title and every voyage share real geography, including styles and collision.
// Leave the surrounding home chunks open so random offshore land cannot overlap it.
public static class StartingArea
{
    public const float HarborRadius = 280;
    public static readonly Vector2 Harbor = new(-120, -490);
    public static readonly Vector2 RepairBerth = Harbor + new Vector2(390, 250);
    public static readonly Vector2 RepairMooring = Harbor +
        new Vector2(HarborDock.CenterX + HarborDock.PostSide, HarborDock.FirstPost + HarborDock.PostStep) * HarborRadius;
    // Alongside the outer dock, with bow/stern clearance for every boat.
    public static readonly Vector2 Spawn = Harbor + new Vector2(295, 295);
    public static readonly IReadOnlyList<Place> Places = Array.AsReadOnly<Place>([
        new("home:harbor", PlaceKind.Harbor, Harbor, HarborRadius, 147),
        new("home:island", PlaceKind.Island, new(990, 275), 125, 921),
        new("home:upper-rock", PlaceKind.Rock, new(1050, -625), 40, 73),
        new("home:current", PlaceKind.Current, new(1250, -160), 245, 0),
        new("home:supplies:east", PlaceKind.Barrel, new(800, 600), 23, 143),
        new("home:supplies:south", PlaceKind.Barrel, new(-270, 990), 23, 334),
        new("home:supplies:west", PlaceKind.Barrel, new(-841, -50), 23, 581)
    ]);
    public static bool Contains(ChunkKey key) => Math.Abs(key.X) <= 1 && Math.Abs(key.Y) <= 1;
    public static OceanChunk Generate(ChunkKey key)
    {
        var places = Places.Where(p => OceanWorld.KeyAt(p.Position) == key).ToList();
        foreach (var island in places.Where(p => p.Kind == PlaceKind.Island).ToArray())
            if (OceanWorld.IslandTreasure(island) is { } chest) places.Add(chest);
        return new(key, places.ToArray());
    }
}

public static class HarborDock
{
    public const float CenterX = .56f;
    public const float FirstBoard = .40f;
    public const float BoardStep = .095f;
    public const int BoardCount = 11;
    public const float BoardDepth = .09f;
    public const float PostSide = .25f;
    public const float PostRadius = .049f;
    public const float FirstPost = .48f;
    public const float PostStep = .43f;

    const float Start = FirstBoard - BoardDepth / 2;
    const float End = FirstBoard + (BoardCount - 1) * BoardStep + BoardDepth / 2;
    static readonly Vector2 Center = new(CenterX, (Start + End) / 2);
    static readonly Vector2 HalfSize = new(PostSide + PostRadius, (End - Start) / 2);
    public static float Bounds { get; } = (Center + HalfSize).Length();

    public static float Overlap(Vector2 offset, float radius, float clearance, out Vector2 normal)
    {
        var local = offset - Center * radius;
        var extents = HalfSize * radius;
        var delta = local - Vector2.Clamp(local, -extents, extents);
        float gap = delta.Length();
        if (gap > .001f)
        {
            normal = delta / gap;
            return clearance - gap;
        }

        var inside = extents - Vector2.Abs(local);
        normal = inside.X < inside.Y ? new(MathF.CopySign(1, local.X), 0) : new(0, MathF.CopySign(1, local.Y));
        return clearance + Math.Min(inside.X, inside.Y);
    }
}
