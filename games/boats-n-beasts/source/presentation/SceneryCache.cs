using Godot;
using BoatsNBeasts.Core;
namespace BoatsNBeasts;

// Bake immutable island/rock geometry in engine space. Retain only loaded-world entries.
// Water, safety rings, fishing, wakes, boats and combat effects remain animated separately.
public partial class SceneryCache : Node
{
    sealed record Entry(SubViewport Viewport, int Size, ulong ReadyFrame);
    readonly Dictionary<string, Entry> entries = new();
    public int Count => entries.Count;
    public void Clear() { foreach (var entry in entries.Values) entry.Viewport.QueueFree(); entries.Clear(); }
    public static float Margin(Place p) => p.Kind == PlaceKind.Harbor ? 240 : p.Kind == PlaceKind.Island ? p.Radius * 1.4f + 25 : p.Radius * 1.3f + 15;
    public void Sync(IReadOnlyList<Place> places, Vector2 camera, Vector2 screenSize)
    {
        var live = places.Select(p => p.Id).ToHashSet();
        foreach (var id in entries.Keys.ToArray())
            if (!live.Contains(id)) { entries[id].Viewport.QueueFree(); entries.Remove(id); }
        int created = 0;
        foreach (var p in places)
        {
            if (!OceanWorld.IsSolid(p) || entries.ContainsKey(p.Id)) continue;
            var at = OceanView.G(p.Position) - camera + screenSize / 2; float margin = Margin(p) + 80;
            if (at.X < -margin || at.Y < -margin || at.X > screenSize.X + margin || at.Y > screenSize.Y + margin) continue;
            int size = (int)MathF.Ceiling(Margin(p) * 2);
            var viewport = new SubViewport { Size = new(size * 2, size * 2), TransparentBg = true, Disable3D = true, RenderTargetUpdateMode = SubViewport.UpdateMode.Once };
            AddChild(viewport); viewport.AddChild(new Stamp { Place = p, Size = size, Scale = Vector2.One * 2 });
            entries.Add(p.Id, new(viewport, size, Engine.GetProcessFrames() + 2));
            if (++created == 2) break;
        }
    }
    public bool Draw(Node2D canvas, Place p, Vector2 at)
    {
        if (!entries.TryGetValue(p.Id, out var entry) || Engine.GetProcessFrames() < entry.ReadyFrame) return false;
        canvas.DrawTextureRect(entry.Viewport.GetTexture(), new Rect2(at - Vector2.One * entry.Size / 2, Vector2.One * entry.Size), false);
        return true;
    }
    partial class Stamp : Node2D
    {
        public Place Place = null!; public int Size;
        public override void _Draw()
        {
            var art = new ProceduralArt(this); var center = Vector2.One * Size / 2;
            if (Place.Kind == PlaceKind.Rock) art.Rocks(center, Place.Radius, Place.Style);
            else art.Island(center, Place.Kind == PlaceKind.Harbor ? 156 : Place.Radius * 1.15f, Place.Style, Place.Kind == PlaceKind.Harbor, 0);
        }
    }
}
