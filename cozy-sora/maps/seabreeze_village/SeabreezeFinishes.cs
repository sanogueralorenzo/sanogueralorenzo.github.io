using Godot;

namespace CozySora;

/// <summary>Procedural building finishes, cached per settlement owner and palette.</summary>
public sealed class SeabreezeFinishes
{
    private readonly Dictionary<(string Kind, string Tint), Material> _finishes = new();
    private StandardMaterial3D? _chainlink;

    public Material Surface(string kind, string tint)
    {
        var key = (kind, tint);
        if (_finishes.TryGetValue(key, out var cached)) return cached;
        var color = new Color(tint);
        ShaderMaterial material;
        if (kind == "glass") material = CozyGlazing.Create(color);
        else
        {
            material = new ShaderMaterial { Shader = GD.Load<Shader>("res://maps/seabreeze_village/architecture.gdshader") };
            material.SetShaderParameter("pigment", color);
            material.SetShaderParameter("finish", kind switch
            {
                "wood" => 1,
                "metal" => 2,
                "tile" => 3,
                "stone" => 4,
                "bamboo" or "pole" => 5,
                "asphalt" => 6,
                _ => 0
            });
        }
        _finishes.Add(key, material);
        return material;
    }

    public StandardMaterial3D Chainlink()
    {
        if (_chainlink is not null) return _chainlink;
        var image = Image.CreateEmpty(64, 64, false, Image.Format.Rgba8);
        // Transparent black preserves the wire colour through alpha mip filtering.
        image.Fill(new Color(0, 0, 0, 0));
        for (int y = 0; y < 64; y++)
            for (int x = 0; x < 64; x++)
                if (Math.Abs(x - y) < 2 || Math.Abs(x + y - 63) < 2) image.SetPixel(x, y, new Color("9eafa5"));
        image.GenerateMipmaps();
        var material = new StandardMaterial3D
        {
            AlbedoTexture = ImageTexture.CreateFromImage(image),
            Transparency = BaseMaterial3D.TransparencyEnum.AlphaScissor,
            AlphaScissorThreshold = .3f,
            CullMode = BaseMaterial3D.CullModeEnum.Disabled,
            Roughness = .9f
        };
        _chainlink = material;
        return material;
    }
}
