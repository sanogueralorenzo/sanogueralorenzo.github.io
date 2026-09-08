using System.Numerics;
namespace BoatsNBeasts.Core;

// The title and every voyage share real geography, including styles and collision.
// Leave the surrounding home chunks open so random offshore land cannot overlap it.
public static class StartingArea
{
    public static readonly Vector2 Spawn = Vector2.Zero;
    public static readonly Vector2 Harbor = new(-120, -490);
    public static readonly Vector2 Departure = new(0, -150);
    public static readonly IReadOnlyList<Place> Places = Array.AsReadOnly<Place>([
        new("home:harbor", PlaceKind.Harbor, Harbor, 140, 147),
        new("home:island", PlaceKind.Island, new(990, 275), 125, 921),
        new("home:upper-rock", PlaceKind.Rock, new(1050, -625), 40, 73),
        new("home:left-rock", PlaceKind.Rock, new(-325, 95), 32, 42),
        new("home:lower-rock", PlaceKind.Rock, new(-105, 205), 36, 104),
        new("home:school", PlaceKind.Fishing, new(-260, -180), 76, 3819),
        new("home:treasure", PlaceKind.Treasure, new(-240, -15), 22, 31),
        new("home:current", PlaceKind.Current, new(1250, -160), 245, 0),
        new("home:wreck", PlaceKind.Wreck, new(-215, 140), 65, 59)
    ]);
    public static bool Contains(ChunkKey key) => Math.Abs(key.X) <= 1 && Math.Abs(key.Y) <= 1;
    public static OceanChunk Generate(ChunkKey key) => new(key, Places.Where(p => OceanWorld.KeyAt(p.Position) == key).ToArray());
}
