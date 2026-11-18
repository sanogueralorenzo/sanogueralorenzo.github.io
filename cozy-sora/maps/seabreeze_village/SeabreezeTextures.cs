using Godot;

namespace CozySora;

public static class SeabreezeTextures
{
    public static Texture2D LeafTexture(int seed_value, bool small = false)
    {
        var random = new SeabreezeRandom();
        random.Seed = (uint)seed_value;
        var image = Image.CreateEmpty(256, 256, false, Image.Format.Rgba8);
        image.Fill(Colors.Transparent);
        for (int stem = 0; stem < 12; stem++)
        {
            float angle = stem * Mathf.Tau / 12 + random.RandfRange(-.19f, .19f);
            var direction = Vector2.Right.Rotated(angle);
            var start = new Vector2(128, 128) + direction * random.RandfRange(1, 14);
            var end = start + direction * random.RandfRange(70, 101);
            var bow = direction.Orthogonal() * random.RandfRange(-19, 19);
            for (int pair = 0; pair < 8; pair++)
            {
                float t = (pair + 1) / 9f;
                float previous = pair / 9f;
                var node = start.Lerp(end, t) + bow * Mathf.Sin(t * Mathf.Pi);
                var last = start.Lerp(end, previous) + bow * Mathf.Sin(previous * Mathf.Pi);
                PaintStroke(image, last, node, 1, new Color(.37f, .35f, .28f));
                for (int side = -1; side <= 1; side += 2)
                {
                    float length = (small ? 21 : 30) * (1 - t * .4f) * random.RandfRange(.78f, 1.3f);
                    var blade = direction.Rotated(side * random.RandfRange(.65f, 1.26f));
                    float shade = random.RandfRange(.54f, .94f);
                    CozyLeafPainter.Paint(image, node + blade * length * .38f, length, length * .57f,
                        blade.Angle() - Mathf.Pi / 2, shade, CozyLeafPainter.Profile.Rounded);
                }
            }
        }
        image.FixAlphaEdges();
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
    public static Texture2D FlowerTexture(Color color, int seed_value)
    {
        var random = new SeabreezeRandom();
        random.Seed = (uint)seed_value;
        var image = Image.CreateEmpty(256, 256, false, Image.Format.Rgba8);
        image.Fill(Colors.Transparent);
        for (int i = 0; i < 5; i += 1)
        {
            int x = random.RandiRange(40, 216);
            int y = random.RandiRange(40, 128);
            for (int sy = y; sy < 256; sy += 1)
            {
                for (int sx = -2; sx < 3; sx += 1)
                {
                    image.SetPixel(Math.Clamp(x + sx + (int)(Mathf.Sin(sy * 0.025f + i) * 5), 0, 255), sy, new Color("5b7c32"));
                }
            }
            int petalCount = random.RandiRange(6, 9);
            float turn = random.RandfRange(0, Mathf.Tau);
            float length = random.RandfRange(11, 16);
            for (int dy = -17; dy <= 17; dy++)
                for (int dx = -17; dx <= 17; dx++)
                {
                    float angle = Mathf.Atan2(dy * 1.18f, dx) + turn;
                    float radius = Mathf.Sqrt(dx * dx + dy * dy * 1.39f);
                    float lobe = .5f + .5f * Mathf.Cos(angle * petalCount);
                    float edge = length * (.35f + .65f * Mathf.Pow(lobe, .38f));
                    if (radius > edge) continue;
                    float fold = (.58f + .42f * lobe) * Mathf.Lerp(.73f, 1, radius / length);
                    image.SetPixel(x + dx, y + dy, new Color(color.R * fold, color.G * fold, color.B * fold));
                }
            for (int dy = -3; dy < 4; dy += 1)
            {
                for (int dx = -3; dx < 4; dx += 1)
                {
                    if (dx * dx + dy * dy < 10)
                    {
                        image.SetPixel(x + dx, y + dy, new Color("ffd54a"));
                    }
                }
            }
        }
        image.GenerateMipmaps();
        return ImageTexture.CreateFromImage(image);
    }
    public static Texture2D PineNeedleTexture()
    {
        var random = new SeabreezeRandom();
        random.Seed = 79;
        var image = Image.CreateEmpty(512, 512, false, Image.Format.Rgba8);
        image.Fill(Colors.Transparent);
        for (int cluster = 0; cluster < 70; cluster += 1)
        {
            float angle = (float)random.Randf() * Mathf.Tau;
            float radius = Mathf.Sqrt((float)random.Randf()) * 153.6f;
            var center = new Vector2(256 + Mathf.Cos(angle) * radius, 256 + Mathf.Sin(angle) * radius);
            float shade = (120 + Mathf.Floor((float)random.Randf() * 110) - Mathf.Floor(radius / 153.6f * 30)) / 255;
            int count = random.RandiRange(9, 14);
            float direction = (float)random.Randf() * Mathf.Tau;
            for (int needle = 0; needle < count; needle += 1)
            {
                float theta = direction + ((float)(needle) / count - 0.5f) * 2.2f;
                float length = random.RandfRange(26, 56);
                PaintStroke(image, center, center + new Vector2(Mathf.Cos(theta), Mathf.Sin(theta)) * length, 3, new Color(shade, shade, shade));
            }
        }
        image.GenerateMipmaps();
        return ImageTexture.CreateFromImage(image);
    }
    public static void PaintDisc(Image image, Vector2 center, float radius, Color color)
    {
        for (int y = Math.Max(0, Mathf.FloorToInt(center.Y - radius)); y < Math.Min(image.GetHeight(), Mathf.CeilToInt(center.Y + radius) + 1); y += 1)
        {
            for (int x = Math.Max(0, Mathf.FloorToInt(center.X - radius)); x < Math.Min(image.GetWidth(), Mathf.CeilToInt(center.X + radius) + 1); x += 1)
            {
                if (new Vector2(x, y).DistanceSquaredTo(center) <= radius * radius)
                {
                    image.SetPixel(x, y, image.GetPixel(x, y).Blend(color));
                }
            }
        }
    }
    public static void PaintStroke(Image image, Vector2 start, Vector2 end, float width, Color color)
    {
        int steps = Math.Max(1, Mathf.CeilToInt(start.DistanceTo(end)));
        for (int i = 0; i < steps + 1; i += 1)
        {
            PaintDisc(image, start.Lerp(end, (float)(i) / steps), width * 0.5f, color);
        }
    }
    public static void PaintEllipse(Image image, Vector2 center, Vector2 radii, Color color)
    {
        for (int y = Math.Max(0, Mathf.FloorToInt(center.Y - radii.Y)); y < Math.Min(image.GetHeight(), Mathf.CeilToInt(center.Y + radii.Y) + 1); y += 1)
        {
            for (int x = Math.Max(0, Mathf.FloorToInt(center.X - radii.X)); x < Math.Min(image.GetWidth(), Mathf.CeilToInt(center.X + radii.X) + 1); x += 1)
            {
                if (((new Vector2(x, y) - center) / radii).LengthSquared() <= 1)
                {
                    image.SetPixel(x, y, image.GetPixel(x, y).Blend(color));
                }
            }
        }
    }
    public static Texture2D ShrineFlowerTexture(string kind, int seed_value)
    {
        var random = new SeabreezeRandom();
        random.Seed = (uint)seed_value;
        var image = Image.CreateEmpty(128, 384, false, Image.Format.Rgba8);
        image.Fill(Colors.Transparent);
        if (kind == "aster")
        {
            int flowerCount = 2 + (random.Randf() < .5 ? 1 : 0);
            for (int i = 0; i < flowerCount; i += 1)
            {
                var center = new Vector2(40 + (i % 2) * 48 + random.RandfRange(-6, 6), 40 + i * 66 + (float)random.Randf() * 24);
                float radius = random.RandfRange(31, 36);
                int petals = random.RandiRange(12, 14);
                float phase = (float)random.Randf() * Mathf.Pi;
                for (int petal = 0; petal < petals; petal += 1)
                {
                    float angle = (float)(petal) / petals * Mathf.Tau + phase;
                    float length = radius * random.RandfRange(0.88f, 1.02f);
                    PaintStroke(image, center, center + new Vector2(Mathf.Cos(angle), Mathf.Sin(angle)) * length, 12, new Color("a894d2"));
                }
                PaintDisc(image, center, radius * 0.62f, new Color("a894d2"));
                PaintDisc(image, center, 11, new Color("e6bc4e"));
            }
            PaintEllipse(image, new Vector2(random.RandfRange(40, 88), random.RandfRange(210, 260)), new Vector2(10, 14), new Color("9a86c6"));
        }
        else if (kind == "buttercup")
        {
            for (int stalk = 0; stalk < 2; stalk += 1)
            {
                float x = 34 + stalk * 60 + random.RandfRange(-7, 7);
                float y = random.RandfRange(44, 114);
                int bloomCount = 2 + (random.Randf() < .5 ? 1 : 0);
                for (int bloom = 0; bloom < bloomCount; bloom += 1)
                {
                    PaintDisc(image, new Vector2(x + random.RandfRange(-11, 11), y + bloom * random.RandfRange(36, 48) - 4), random.RandfRange(21, 24), new Color("eeae36"));
                }
            }
        }
        else
        {
            for (int stalk = 0; stalk < 2; stalk += 1)
            {
                var center = new Vector2(32 + stalk * 64 + random.RandfRange(-8, 8), random.RandfRange(44, 104));
                for (int petal = 0; petal < 6; petal += 1)
                {
                    PaintDisc(image, center + new Vector2(random.RandfRange(-11, 11), random.RandfRange(-11, 11)), random.RandfRange(13, 18), new Color("dd4b56"));
                }
            }
        }
        return ImageTexture.CreateFromImage(image);
    }
    public static ShaderMaterial GiantBarkMaterial(Vector3 origin)
    {
        var random = new SeabreezeRandom();
        random.Seed = 21;
        var image = Image.CreateEmpty(128, 512, false, Image.Format.Rgba8);
        image.Fill(Color.Color8(118, 118, 108));
        for (int i = 0; i < 140; i += 1)
        {
            int change = random.RandiRange(-30, 19);
            var color = new Color((118 + change) / 255.0f, (118 + change) / 255.0f, (108 + change) / 255.0f, random.RandfRange(0.35f, 0.75f));
            var rect = new Rect2I(random.RandiRange(0, 127), random.RandiRange(0, 511), random.RandiRange(2, 7), random.RandiRange(30, 150));
            for (int y = rect.Position.Y; y < Math.Min(512, rect.End.Y); y += 1)
            {
                for (int x = rect.Position.X; x < Math.Min(128, rect.End.X); x += 1)
                {
                    image.SetPixel(x, y, image.GetPixel(x, y).Blend(color));
                }
            }
        }
        for (int i = 0; i < 60; i += 1)
        {
            var p = new Vector2((float)random.Randf() * 128, (float)random.Randf() * 512);
            PaintStroke(image, p, p + new Vector2(0, random.RandfRange(20, 100)), random.RandfRange(1, 3), new Color(20 / 255.0f, 14 / 255.0f, 10 / 255.0f, random.RandfRange(0.25f, 0.6f)));
        }
        for (int i = 0; i < 70; i += 1)
        {
            PaintEllipse(image, new Vector2((float)random.Randf() * 128, (float)random.Randf() * 512), new Vector2(random.RandfRange(4, 14), random.RandfRange(8, 34)), new Color(94 / 255.0f, 126 / 255.0f, 92 / 255.0f, random.RandfRange(0.25f, 0.6f)));
        }
        for (int i = 0; i < 30; i += 1)
        {
            PaintEllipse(image, new Vector2((float)random.Randf() * 128, (float)random.Randf() * 512), new Vector2(random.RandfRange(3, 9), random.RandfRange(6, 24)), new Color(158 / 255.0f, 156 / 255.0f, 142 / 255.0f, random.RandfRange(0.2f, 0.5f)));
        }
        for (int pass_index = 0; pass_index < 2; pass_index += 1)
        {
            for (int i = 0; i < (pass_index == 0 ? 70 : 60); i += 1)
            {
                var start = new Vector2((float)random.Randf() * 128, (float)random.Randf() * 512 - 40);
                float length = random.RandfRange(40, 180);
                float drift = random.RandfRange(-7, 7);
                var color = ((pass_index == 0 ? new Color(152 / 255.0f, 152 / 255.0f, 136 / 255.0f, random.RandfRange(0.55f, 0.9f)) : new Color(72 / 255.0f, 70 / 255.0f, 62 / 255.0f, random.RandfRange(0.6f, 0.95f))));
                float width = random.RandfRange(2, 4);
                var previous = start;
                for (int step = 1; step < 13; step += 1)
                {
                    float t = (float)(step) / 12;
                    var p = start + new Vector2(Mathf.Sin(t * Mathf.Pi) * drift, length * t);
                    PaintStroke(image, previous, p, width, color);
                    previous = p;
                }
            }
        }
        for (int i = 0; i < 4; i += 1)
        {
            float x = (i + 0.3f + (float)random.Randf() * 0.5f) / 4 * 128;
            var previous = new Vector2(x, -10);
            for (int step = 1; step < 25; step += 1)
            {
                var p = new Vector2(x + Mathf.Sin(step * 0.21f + i) * 8, step / 24.0f * 532 - 10);
                PaintStroke(image, previous, p, 4, new Color(72 / 255.0f, 70 / 255.0f, 62 / 255.0f, 0.9f));
                PaintStroke(image, previous + new Vector2(4, 0), p + new Vector2(4, 0), 2, new Color(152 / 255.0f, 152 / 255.0f, 136 / 255.0f, 0.5f));
                previous = p;
            }
        }
        image.GenerateMipmaps();
        var shader = GD.Load<Shader>("res://maps/seabreeze_village/giant_bark.gdshader");
        var material = new ShaderMaterial();
        material.Shader = shader;
        material.SetShaderParameter("bark_texture", ImageTexture.CreateFromImage(image));
        material.SetShaderParameter("tree_origin", origin);
        return material;
    }
}
