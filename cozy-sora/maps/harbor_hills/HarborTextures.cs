using Godot;

namespace CozySora;

public static class HarborTextures
{
    public static Texture2D LeafSpray()
    {
        var image = Image.CreateEmpty(256, 256, false, Image.Format.Rgba8);
        image.Fill(Colors.Transparent);
        var rng = new RandomNumberGenerator { Seed = 73421 };
        for (int layer = 0; layer < 2; layer++)
            for (int i = 0; i < 64; i++)
            {
                float angle = rng.Randf() * Mathf.Tau;
                float radius = Mathf.Sqrt(rng.Randf()) * 87;
                var center = new Vector2(128, 128) + new Vector2(Mathf.Cos(angle), Mathf.Sin(angle) * .82f) * radius;
                float length = rng.RandfRange(9, 21);
                float width = length * rng.RandfRange(.28f, .56f);
                float turn = angle + rng.RandfRange(-1.2f, 1.2f);
                float shade = layer == 0 ? rng.RandfRange(.46f, .72f) : rng.RandfRange(.7f, 1);
                CozyLeafPainter.Paint(image, center, length, width, turn, shade, CozyLeafPainter.Profile.Pointed);
            }
        image.GenerateMipmaps();
        return ImageTexture.CreateFromImage(image);
    }
}
