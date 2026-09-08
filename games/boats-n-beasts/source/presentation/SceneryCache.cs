using Godot;
using BoatsNBeasts.Core;
namespace BoatsNBeasts;

// Bake immutable island/rock geometry in engine space. Retain only loaded-world entries.
// Water, safety rings, fishing, wakes, boats and combat effects remain animated separately.
public partial class SceneryCache : Node2D
{
    sealed record Entry(SubViewport Viewport, int Size, ulong ReadyFrame, Place Place);
    Vector2 camera, screenSize;
    public override void _Ready()
    {
        ShowBehindParent = true;
        Material = new ShaderMaterial { Shader = new Shader { Code = "shader_type canvas_item; render_mode blend_premul_alpha;" } };
    }
    public override void _Draw()
    {
        foreach(var entry in entries.Values)
        {
            if(Engine.GetProcessFrames()<entry.ReadyFrame) continue;
            var at=OceanView.G(entry.Place.Position)-camera+screenSize/2;
            DrawTextureRect(entry.Viewport.GetTexture(),new Rect2(at-Vector2.One*entry.Size/2,Vector2.One*entry.Size),false);
        }
    }
    readonly Dictionary<string, Entry> entries = new();
    public int Count => entries.Count;
    public void Clear() { foreach (var entry in entries.Values) entry.Viewport.QueueFree(); entries.Clear(); }
    public static float Margin(Place p) => p.Kind == PlaceKind.Harbor ? 330 : p.Kind == PlaceKind.Island ? p.Radius * 2.25f + 25 : p.Radius * 1.3f + 15;
    public void Sync(IReadOnlyList<Place> places, Vector2 camera, Vector2 screenSize)
    {
        this.camera=camera; this.screenSize=screenSize; QueueRedraw();
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
            entries.Add(p.Id, new(viewport, size, Engine.GetProcessFrames() + 2, p));
            if (++created == 2) break;
        }
    }
    public bool IsReady(Place p)
    {
        if (!entries.TryGetValue(p.Id, out var entry) || Engine.GetProcessFrames() < entry.ReadyFrame) return false;
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
