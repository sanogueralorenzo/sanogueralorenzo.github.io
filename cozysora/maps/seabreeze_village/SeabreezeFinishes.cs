using Godot;

namespace CozySora;

/// <summary>Generated building finishes, cached per settlement owner and palette.</summary>
public sealed class SeabreezeFinishes
{
    private readonly Dictionary<string, StandardMaterial3D> _textures = new();

    public StandardMaterial3D Surface(string kind, string tint)
    {
        string key = kind + tint;
        if (_textures.TryGetValue(key, out var cached)) return cached;
        var image = Image.CreateEmpty(128, 128, false, Image.Format.Rgb8);
        var color = new Color(tint);
        var random = new RandomNumberGenerator { Seed = 417 + kind.Hash() };
        for (int y = 0; y < 128; y++)
            for (int x = 0; x < 128; x++)
            {
                float f = random.RandfRange(.94f, 1.05f);
                switch (kind)
                {
                    case "wood":
                        f *= x % 8 < 1 ? .55f : 1;
                        f += Mathf.Sin(y * .19f + Mathf.Sin(x * 2.7f)) * .035f;
                        break;
                    case "pole":
                        f *= .88f + Mathf.Sin(x * 2.4f) * .08f;
                        if (y % 29 < 2) f *= .8f;
                        break;
                    case "bamboo":
                        f *= y % 4 == 0 ? .55f : 1;
                        f *= x % 42 < 2 ? .75f : 1;
                        break;
                    case "metal": f *= (.84f + Mathf.Sin(x % 8 * Mathf.Pi / 4) * .13f) * .58f; break;
                    case "tile":
                        f *= y % 32 < 6 ? .34f : 1;
                        f *= .85f + Mathf.Sin(x % 16 * Mathf.Pi / 16) * .2f;
                        break;
                    case "paint":
                        f *= .9f + Mathf.Sin(x * .08f + Mathf.Sin(y * .05f) * 2) * .05f;
                        if (random.Randf() < .025f) f *= .64f;
                        break;
                    case "stone": f *= y % 32 < 2 || (x + y / 32 * 16) % 48 < 2 ? .70f : 1; break;
                }
                image.SetPixel(x, y, new Color(color.R * f, color.G * f, color.B * f));
            }
        if (kind == "stone") RockPattern(image, color, random);
        var material = new StandardMaterial3D { AlbedoTexture = ImageTexture.CreateFromImage(image), Roughness = .93f, Uv1Scale = new(2, 2, 2) };
        _textures.Add(key, material);
        return material;
    }

    private static void RockPattern(Image image, Color color, RandomNumberGenerator random)
    {
        image.Fill(color * .5f);
        for (int i = 0; i < 60; i++)
        {
            float x = random.RandfRange(-12, 126), y = random.RandfRange(-12, 126);
            float width = random.RandfRange(11, 28), height = random.RandfRange(8, 20);
            Vector2[] polygon = [new(x, y + height * .3f), new(x + width * .3f, y), new(x + width, y + height * .2f), new(x + width * .9f, y + height), new(x + width * .2f, y + height * .95f)];
            var rock = color * random.RandfRange(.85f, 1.24f);
            for (int yy = Math.Max(0, (int)y); yy < Math.Min(128, (int)(y + height) + 1); yy++)
                for (int xx = Math.Max(0, (int)x); xx < Math.Min(128, (int)(x + width) + 1); xx++)
                    if (Geometry2D.IsPointInPolygon(new(xx, yy), polygon)) image.SetPixel(xx, yy, rock * random.RandfRange(.94f, 1.03f));
        }
    }

    public StandardMaterial3D Chainlink()
    {
        if (_textures.TryGetValue("chainlink", out var cached)) return cached;
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
        _textures.Add("chainlink", material);
        return material;
    }
}
