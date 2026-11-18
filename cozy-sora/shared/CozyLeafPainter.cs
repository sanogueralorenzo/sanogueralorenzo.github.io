using Godot;

namespace CozySora;

/// <summary>Bounded rasterization of the original two procedural silhouettes; consumes no random draws.</summary>
public static class CozyLeafPainter
{
    public enum Profile { Rounded, Pointed }

    public static Texture2D Spray(ulong seed, float leafLength, float leafWidth)
    {
        const int resolution = 256;
        using var image = Image.CreateEmpty(resolution, resolution, false, Image.Format.Rgba8);
        var random = new RandomNumberGenerator { Seed = seed };
        for (int twig = 0; twig < 12; twig++)
        {
            float angle = twig * Mathf.Tau / 12 + random.RandfRange(-.24f, .24f);
            var axis = Vector2.Right.Rotated(angle);
            var across = axis.Orthogonal();
            var basePoint = new Vector2(128, 128) + axis * random.RandfRange(3, 16);
            float reach = random.RandfRange(65, 96);
            float arc = random.RandfRange(-20, 20);
            Vector2 Along(float t) => basePoint + axis * (t * reach) + across * (t * t * arc);
            for (int pixel = 0; pixel < (int)reach; pixel++)
            {
                var dot = Along(pixel / reach);
                image.SetPixel((int)dot.X, (int)dot.Y, new Color(.27f, .28f, .20f));
            }
            for (int pair = 0; pair < 8; pair++)
                for (int side = -1; side <= 1; side += 2)
                {
                    float t = (.70f + pair + (side > 0 ? .25f : 0)) / 9;
                    float size = leafLength * Mathf.Lerp(1.15f, .64f, t) * random.RandfRange(.72f, 1.27f);
                    float turn = angle + side * random.RandfRange(.45f, 1.08f);
                    var blade = Vector2.Right.Rotated(turn);
                    Paint(image, Along(t) + blade * size * .70f, size, size * leafWidth, turn,
                        random.RandfRange(.55f, .95f) * (.85f + .15f * t), Profile.Pointed);
                }
        }
        image.FixAlphaEdges();
        image.GenerateMipmaps();
        return ImageTexture.CreateFromImage(image);
    }

    public static void Paint(Image image, Vector2 center, float length, float width, float angle, float shade,
        Profile profile, bool outline = false)
    {
        bool rounded = profile == Profile.Rounded;
        int extent = Mathf.CeilToInt(length * .6f + width * .6f);
        int left = rounded ? (int)center.X - extent : (int)(center.X - length);
        int right = rounded ? (int)center.X + extent + 1 : (int)(center.X + length + 1);
        int top = rounded ? (int)center.Y - extent : (int)(center.Y - length);
        int bottom = rounded ? (int)center.Y + extent + 1 : (int)(center.Y + length + 1);
        var axis = new Vector2(Mathf.Cos(angle), Mathf.Sin(angle));
        var side = new Vector2(-axis.Y, axis.X);
        for (int y = Math.Max(0, top); y < Math.Min(image.GetHeight(), bottom); y++)
            for (int x = Math.Max(0, left); x < Math.Min(image.GetWidth(), right); x++)
            {
                var delta = new Vector2(x, y) - center;
                if (rounded)
                {
                    var point = delta.Rotated(-angle);
                    float v = point.Y / (length * .5f);
                    if (Mathf.Abs(v) >= 1) continue;
                    float halfWidth = width * .5f * Mathf.Pow(1 - v * v, .8f);
                    if (Mathf.Abs(point.X) > halfWidth) continue;
                    float across = point.X / halfWidth;
                    float rib = Mathf.Exp(-Mathf.Abs(point.X) * 1.55f);
                    float veins = Mathf.Abs(Mathf.Sin((v - Mathf.Abs(across) * .38f) * 16));
                    float relief = .89f + across * .09f + rib * .17f;
                    relief += .045f * (1 - Mathf.SmoothStep(.06f, .30f, veins));
                    if (outline) relief -= .08f * Mathf.SmoothStep(.82f, 1, Mathf.Abs(across));
                    float ink = shade * relief;
                    image.SetPixel(x, y, new Color(ink * .96f, ink, ink * .91f, 1));
                }
                else
                {
                    float u = delta.Dot(axis) / length;
                    float v = delta.Dot(side) / width;
                    float edge = u * u + v * v * (1 + Mathf.Abs(u) * .7f);
                    if (edge > 1) continue;
                    float tint = shade * (.88f + .12f * (1 - v));
                    if (edge > .78f) tint *= .72f;
                    if (Mathf.Abs(v) < .055f) tint *= .73f;
                    image.SetPixel(x, y, new Color(tint * .94f, tint, tint * .85f, Mathf.Clamp((1 - edge) * 8, 0, 1)));
                }
            }
    }
}
