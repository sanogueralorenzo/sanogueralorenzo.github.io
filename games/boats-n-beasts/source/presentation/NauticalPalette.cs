using Godot;
namespace BoatsNBeasts;

public static class NauticalPalette
{
    public static readonly Color Cream = new("ffe5af"), Coral = new("ff7651"), Aqua = new("63dccc"), Navy = new("0a2939");
    public static Vector2 G(System.Numerics.Vector2 value) => new(value.X, value.Y);
}
