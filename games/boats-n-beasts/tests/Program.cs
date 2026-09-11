using System.Numerics;
using BoatsNBeasts.Core;

static void Check(bool condition, string message)
{
    if (!condition) throw new Exception(message);
}

var wreck = new Place("wreck-check", PlaceKind.Shipwreck, new(350, -210), 220, 15);
Check(OceanWorld.IsSolid(wreck), "Sea wreck must be a solid obstacle.");
Check(OceanWorld.Overlap(wreck, wreck.Position, 0, out var normal, out float depth), "Hull center must collide.");
Check(float.IsFinite(normal.X) && float.IsFinite(normal.Y) && depth > 0, "Hull center must produce a valid push-out.");
var pushed = wreck.Position + normal * (depth + .01f);
Check(!OceanWorld.Overlap(wreck, pushed, 0, out _, out _), "Collision push-out must leave the hull.");
var axis = new Vector2(MathF.Cos(-.55f), -MathF.Sin(-.55f));
var across = new Vector2(-axis.Y, axis.X);
Check(!OceanWorld.Overlap(wreck, wreck.Position + across * 120, 0, out _, out _), "Water beside the hull must stay navigable.");
Check(OceanWorld.Overlap(wreck, wreck.Position + across * 80, 18, out _, out _), "Player radius must be included at the hull edge.");
Check(!OceanWorld.Overlap(wreck, wreck.Position + axis * 205, 0, out _, out _), "Water beyond the stern must stay navigable.");
foreach (float scale in new[] { .5f, 2f })
{
    var resized = wreck with { Radius = wreck.Radius * scale };
    Check(OceanWorld.Overlap(resized, resized.Position + across * (60 * scale), 0, out _, out _), "Collision must scale with the wreck.");
    Check(!OceanWorld.Overlap(resized, resized.Position + across * (100 * scale), 0, out _, out _), "Scaled clearance must remain open water.");
}

var keys = (from y in Enumerable.Range(10, 9) from x in Enumerable.Range(10, 9) select new ChunkKey(x, y)).ToArray();
var world = new OceanWorld(147);
var forward = keys.ToDictionary(k => k, k => world.Generate(k).Places);
var reverse = keys.Reverse().ToDictionary(k => k, k => new OceanWorld(147).Generate(k).Places);
foreach (var key in keys)
{
    // Compare world data, excluding each instance's lazily cached IslandShape object.
    static object Data(Place p) => (p.Id, p.Kind, p.Position, p.Radius, p.Style, p.Heading);
    Check(forward[key].Select(Data).SequenceEqual(reverse[key].Select(Data)), "Scenery must be independent of chunk generation order.");
}
var places = forward.Values.SelectMany(p => p).ToArray();
var wrecks = places.Where(p => p.Kind == PlaceKind.Shipwreck).ToArray();
Check(wrecks.Length > 0, "The generation sample must actually contain sea wrecks.");
foreach (var seaWreck in wrecks)
foreach (var solid in places.Where(OceanWorld.IsSolid).Where(p => p.Id != seaWreck.Id))
    Check(Vector2.Distance(seaWreck.Position, solid.Position) > seaWreck.Radius + solid.Radius, "A sea wreck overlaps another obstacle.");
Console.WriteLine($"Passed hull collision, scaling, push-out, deterministic generation and spacing checks ({keys.Length} chunks, {wrecks.Length} sea wrecks).");
