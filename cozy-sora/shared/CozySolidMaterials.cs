using Godot;

namespace CozySora;

/// <summary>Each owner retains its own mutable palette materials.</summary>
public sealed class CozySolidMaterials
{
    private readonly Dictionary<string, StandardMaterial3D> _materials = new();

    public StandardMaterial3D Color(string hex)
    {
        if (_materials.TryGetValue(hex, out var existing)) return existing;
        var material = new StandardMaterial3D
        {
            AlbedoColor = new Color(hex),
            Roughness = 1,
            DiffuseMode = BaseMaterial3D.DiffuseModeEnum.Toon,
            SpecularMode = BaseMaterial3D.SpecularModeEnum.Disabled
        };
        _materials.Add(hex, material);
        return material;
    }
}
