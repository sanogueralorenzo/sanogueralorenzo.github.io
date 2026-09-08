// Adapted directly from project-owned CozySora source; see docs/REDESIGN.md.
using Godot;

namespace Further.Salvage;

/// <summary>Bounded rasterization of the original two procedural silhouettes; consumes no random draws.</summary>
public static class CozyLeafPainter
{
    public enum Profile { Rounded, Pointed }

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
                    float ink = shade - (outline && Mathf.Abs(point.X) > halfWidth - .9f ? .27f : 0);
                    image.SetPixel(x, y, new Color(ink, ink, ink, 1));
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
