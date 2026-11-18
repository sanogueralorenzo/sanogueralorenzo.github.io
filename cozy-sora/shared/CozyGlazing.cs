using Godot;

namespace CozySora;

public static class CozyGlazing
{
    public static ShaderMaterial Create(Color tint)
    {
        var material = new ShaderMaterial { Shader = GD.Load<Shader>("res://shaders/glazing.gdshader") };
        material.SetShaderParameter("glass_tint", tint);
        return material;
    }
}
