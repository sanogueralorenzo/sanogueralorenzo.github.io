using Godot;

namespace Further.Salvage;

public static class SeabreezeTextures
{
    public static Texture2D LeafTexture(int seed_value, bool small = false)
    {
        var random = new SeabreezeRandom();
        random.Seed = (uint)seed_value;
        var image = Image.CreateEmpty(256, 256, false, Image.Format.Rgba8);
        image.Fill(Colors.Transparent);
        for (int pass_index = 0; pass_index < 2; pass_index += 1)
        {
            int count = (pass_index == 0 ? ((small ? 70 : 30)) : ((small ? 154 : 48)));
            for (int i = 0; i < count; i += 1)
            {
                float angle = (float)random.Randf() * Mathf.Tau;
                float radius = Mathf.Sqrt((float)random.Randf()) * ((pass_index == 0 ? 56 : 77));
                var p = new Vector2(128 + Mathf.Cos(angle) * radius, 128 + Mathf.Sin(angle) * radius * 0.9f);
                float factor = (small ? 0.45f : .62f);
                float length = random.RandfRange(40, 75) * factor;
                float width = random.RandfRange(22, 40) * factor;
                float rotation = (float)random.Randf() * Mathf.Tau;
                float shade = ((pass_index == 0 ? random.RandfRange(0.47f, 0.67f) : random.RandfRange(0.63f, 1) - radius / 77 * 0.10f));
                CozyLeafPainter.Paint(image, p, length, width, rotation, shade, CozyLeafPainter.Profile.Rounded, pass_index == 1);
            }
        }
        image.GenerateMipmaps();
        return ImageTexture.CreateFromImage(image);
    }
    public static StandardMaterial3D BarkMaterial()
    {
        var material = new StandardMaterial3D();
        material.AlbedoColor = new Color("4a3a2c");
        material.Roughness = 1;
        var image = Image.CreateEmpty(64, 256, false, Image.Format.Rgb8);
        for (int y = 0; y < 256; y += 1)
        {
            for (int x = 0; x < 64; x += 1)
            {
                float stripe = Mathf.Sin(x * 1.3f + Mathf.Sin(y * 0.025f) * 1.7f) * 0.09f + Mathf.Sin(x * 3.4f + y * 0.04f) * 0.055f;
                image.SetPixel(x, y, new Color(0.82f + stripe, 0.78f + stripe, 0.72f + stripe));
            }
        }
        image.GenerateMipmaps();
        material.AlbedoTexture = ImageTexture.CreateFromImage(image);
        return material;
    }
}
