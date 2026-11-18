using System.Numerics;
using BoatsNBeasts.Core;

static void Check(bool condition, string message)
{
    if (!condition) throw new Exception(message);
}

var keys = (from y in Enumerable.Range(10, 9) from x in Enumerable.Range(10, 9) select new ChunkKey(x, y)).ToArray();
var world = new OceanWorld(147);
var forward = keys.ToDictionary(k => k, k => world.Generate(k).Places);
var reverseWorld = new OceanWorld(147);
var reverse = keys.Reverse().ToDictionary(k => k, k => reverseWorld.Generate(k).Places);
foreach (var key in keys)
{
    // Compare world data, excluding each instance's lazily cached IslandShape object.
    static object Data(Place p) => (p.Id, p.Kind, p.Position, p.Radius, p.Style, p.Heading);
    Check(forward[key].Select(Data).SequenceEqual(reverse[key].Select(Data)), "Scenery must be independent of chunk generation order.");
}
var places = forward.Values.SelectMany(p => p).ToArray();
Console.WriteLine($"Passed deterministic generation checks ({keys.Length} chunks).");

var whirlpools = places.Where(p => p.Kind == PlaceKind.Whirlpool).ToArray();
Check(whirlpools.Length > 0, "The generation sample must contain whirlpools.");
foreach (var vortex in whirlpools)
{
    Check(!OceanWorld.IsSolid(vortex), "A visual whirlpool must not become a collision obstacle.");
    foreach (var obstacle in places.Where(OceanWorld.IsSolid))
        Check(Vector2.Distance(vortex.Position, obstacle.Position) > vortex.Radius + obstacle.Radius,
            "The whirlpool funnel must stay clear of land and solid scenery.");
    world.Stream(vortex.Position);
    Check(world.Places.Any(p => p.Id == vortex.Id), "The whirlpool must be loaded for the flow check.");
    Check(world.FlowAt(vortex.Position).LengthSquared() < .001f, "A visual whirlpool must not pull the boat.");
}
var current = places.First(p => p.Kind == PlaceKind.Current);
world.Stream(current.Position);
Check(Vector2.Dot(world.FlowAt(current.Position), OceanWorld.FlowDirection(current)) > 0,
    "A current must push the boat in its flow direction.");
Console.WriteLine($"Passed open-water whirlpool spacing and visual-only behavior checks ({whirlpools.Length} whirlpools).");
