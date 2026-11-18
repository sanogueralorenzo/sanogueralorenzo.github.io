using Godot;

namespace CozySora;

public static class CozyBark
{
    public static ShaderMaterial Create(Color tint, float furrowScale = 1)
    {
        var material = new ShaderMaterial { Shader = GD.Load<Shader>("res://shaders/bark.gdshader") };
        material.SetShaderParameter("bark_tint", tint);
        material.SetShaderParameter("furrow_scale", furrowScale);
        return material;
    }
}
