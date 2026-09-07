namespace CozySora.Water;

/// <summary>Engine-independent fields, generated once per surface, never loaded from assets.</summary>
public static class WaterFields
{
    // Separable lower envelopes of squared-distance parabolas, with world-space
    // pixel spacing. The signed result interpolates across rasterized shore edges.
    public static float[] ShoreDistance(float[] depth, int size, float stepX, float stepZ)
    {
        float[] ToClass(bool land)
        {
            var field = depth.Select(d => (d <= .002f) == land ? 0f : 1e10f).ToArray();
            var row = new float[size]; var result = new float[size];
            var sites = new int[size]; var cuts = new double[size + 1];
            void Transform(float step)
            {
                double scale = step * step;
                int count = 0; sites[0] = 0; cuts[0] = double.NegativeInfinity; cuts[1] = double.PositiveInfinity;
                for (int q = 1; q < size; q++)
                {
                    double crossing;
                    while (true)
                    {
                        int p = sites[count];
                        crossing = ((double)row[q] - row[p] + scale * (q * q - p * p)) / (2 * scale * (q - p));
                        if (crossing > cuts[count]) break;
                        count--;
                    }
                    sites[++count] = q; cuts[count] = crossing; cuts[count + 1] = double.PositiveInfinity;
                }
                int active = 0;
                for (int q = 0; q < size; q++)
                {
                    while (cuts[active + 1] < q) active++;
                    int delta = q - sites[active];
                    result[q] = (float)(scale * delta * delta + row[sites[active]]);
                }
            }
            for (int z = 0; z < size; z++)
            {
                Array.Copy(field, z * size, row, 0, size); Transform(stepX);
                Array.Copy(result, 0, field, z * size, size);
            }
            for (int x = 0; x < size; x++)
            {
                for (int z = 0; z < size; z++) row[z] = field[z * size + x];
                Transform(stepZ);
                for (int z = 0; z < size; z++) field[z * size + x] = result[z];
            }
            return field;
        }
        var toLand = ToClass(true); var toWater = ToClass(false);
        float halfPixel = Math.Min(stepX, stepZ) * .5f;
        for (int i = 0; i < depth.Length; i++)
            toLand[i] = depth[i] > .002f ? Math.Min(32, MathF.Sqrt(toLand[i]) - halfPixel) : -Math.Min(32, MathF.Sqrt(toWater[i]) - halfPixel);
        return toLand;
    }

    // Periodic, smoothly interpolated value noise: broad wind patches in R,
    // smaller shoreline breakup in G. Texture mipmaps handle distant footprints.
    public static byte[] WindAndShore(int size)
    {
        static float Noise(float x, float y, int period, uint seed)
        {
            int ix = (int)MathF.Floor(x), iy = (int)MathF.Floor(y);
            float tx = x - ix, ty = y - iy;
            tx = tx * tx * tx * (tx * (tx * 6 - 15) + 10);
            ty = ty * ty * ty * (ty * (ty * 6 - 15) + 10);
            float Hash(int a, int b)
            {
                uint h = unchecked((uint)(a % period) * 374761393u + (uint)(b % period) * 668265263u + seed);
                h = (h ^ (h >> 13)) * 1274126177u;
                return (h ^ (h >> 16)) / (float)uint.MaxValue;
            }
            float top = float.Lerp(Hash(ix, iy), Hash(ix + 1, iy), tx);
            float bottom = float.Lerp(Hash(ix, iy + 1), Hash(ix + 1, iy + 1), tx);
            return float.Lerp(top, bottom, ty);
        }
        var pixels = new byte[size * size * 2];
        for (int y = 0; y < size; y++) for (int x = 0; x < size; x++)
        {
            float u = (float)x / size, v = (float)y / size;
            float gust = Noise(u * 4, v * 4, 4, 137) * .65f + Noise(u * 8, v * 8, 8, 271) * .25f + Noise(u * 16, v * 16, 16, 419) * .1f;
            float shore = Noise(u * 8, v * 8, 8, 853) * .55f + Noise(u * 32, v * 32, 32, 947) * .3f + Noise(u * 64, v * 64, 64, 1237) * .15f;
            pixels[(y * size + x) * 2] = (byte)Math.Clamp((int)(gust * 255), 0, 255);
            pixels[(y * size + x) * 2 + 1] = (byte)Math.Clamp((int)(shore * 255), 0, 255);
        }
        return pixels;
    }
}
