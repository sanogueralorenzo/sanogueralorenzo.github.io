using Godot;
namespace BoatsNBeasts;

// Shared, reproducible material grain stays attached to each sculpted mesh.
public static class TactileSurface
{
    static ShaderMaterial? material;
    public static ShaderMaterial Material => material ??= new() { Shader = GD.Load<Shader>("res://source/presentation/tactile-surface.gdshader") };
    public static void Advance(float clock) { if (material != null) material.SetShaderParameter("clock", clock); }
}
