using System.Numerics;
namespace BoatsNBeasts.Core;

// The title and every voyage share real geography, including styles and collision.
// Leave the surrounding home chunks open so random offshore land cannot overlap it.
public static class StartingArea
{
    public static readonly Vector2 Harbor = new(-120, -490);
    // Alongside the outer dock, with bow/stern clearance for every boat.
    public static readonly Vector2 Spawn = Harbor + new Vector2(320, 295);
    public static readonly IReadOnlyList<Place> Places = Array.AsReadOnly<Place>([
        new("home:harbor", PlaceKind.Harbor, Harbor, 280, 147),
        new("home:island", PlaceKind.Island, new(990, 275), 125, 921),
        new("home:upper-rock", PlaceKind.Rock, new(1050, -625), 40, 73),
        new("home:current", PlaceKind.Current, new(1250, -160), 245, 0)
    ]);
    public static bool Contains(ChunkKey key) => Math.Abs(key.X) <= 1 && Math.Abs(key.Y) <= 1;
    public static OceanChunk Generate(ChunkKey key) => new(key, Places.Where(p => OceanWorld.KeyAt(p.Position) == key).ToArray());
}
