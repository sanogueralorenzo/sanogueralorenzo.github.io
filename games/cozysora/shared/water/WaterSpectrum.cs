using System.Numerics;

namespace CozySora.Water;

/// <summary>Engine-independent directional gravity-wave spectrum and CPU surface queries.</summary>
public sealed class WaterSpectrum
{
    public readonly record struct Wave(Vector2 Direction, float Amplitude, float Length, float Speed, float Steepness, float Phase)
    {
        public float Number => MathF.Tau / Length;
    }
    public readonly record struct Sample(float Height, Vector2 Slope, Vector2 Displacement, float VerticalVelocity);
    public IReadOnlyList<Wave> Waves { get; }
    public float MaximumHeight { get; }

    public WaterSpectrum(float amplitudeScale, float lengthScale = 1, float swell = .35f)
    {
        Wave[] families = [
            new(new(.91f,.42f),1.7f,70,.94f,.28f,.18f),
            new(new(-.32f,.95f),.67f,34,1.35f,.22f,1.1f),
            new(new(.7f,-.71f),.27f,12,2.27f,.15f,-.72f),
            new(new(-.96f,-.28f),.085f,5.2f,3.44f,.06f,2.24f)
        ];
        float[] calm = [.44f, .38f, .32f, .26f], longSwell = [1.18f, .84f, .68f, .52f];
        float[] calmSteep = [.64f, .62f, .58f, .52f], swellSteep = [1.08f, .9f, .78f, .72f];
        for (int i = 0; i < 4; i++) families[i] = families[i] with
        {
            Direction = Vector2.Normalize(families[i].Direction),
            Amplitude = families[i].Amplitude * Lerp(calm[i], longSwell[i], swell),
            Steepness = families[i].Steepness * Lerp(calmSteep[i], swellSteep[i], swell)
        };
        List<Wave> waves = [.. families];
        float[] rotation = [-.62f, .78f, -1.05f, 1.26f], amplitude = [.38f, .48f, .52f, .45f];
        float[] length = [1.55f, .64f, .6f, .62f], speed = [.8f, 1.25f, 1.29f, 1.27f];
        float[] steep = [.72f, .9f, .78f, .65f], phase = [1.37f, -1.83f, 2.41f, -2.08f];
        for (int i = 0; i < 4; i++) waves.Add(families[i] with
        {
            Direction = Rotate(families[i].Direction, rotation[i]),
            Amplitude = families[i].Amplitude * amplitude[i],
            Length = families[i].Length * length[i],
            Speed = families[i].Speed * speed[i],
            Steepness = families[i].Steepness * steep[i],
            Phase = families[i].Phase + phase[i]
        });
        float[] energy = [.2f, .17f, .14f, .11f], spread = [-.88f, .53f, -.37f, .91f];
        float[,] bands = { { 1.5f, 1.18f, .79f, .57f }, { 1.37f, 1.06f, .76f, .54f }, { 1.38f, .96f, .69f, .5f }, { 1.34f, 1.04f, .76f, .51f } };
        for (int band = 0; band < 4; band++) for (int family = 0; family < 4; family++)
        {
            var basis = families[family];
            float angle = spread[band] * (.27f + family * .16f) + (Hash(family, band, 11) - .5f) * .095f;
            float wavelength = MathF.Max(2.5f, basis.Length * bands[family, band] * (1 + (Hash(family, band, 29) - .5f) * .072f));
            float spectralWeight = .3f + .7f * MathF.Sqrt(PeakEnergy(wavelength, basis.Length));
            waves.Add(new(Rotate(basis.Direction, angle),
                MathF.Min(basis.Amplitude * .27f, basis.Amplitude * energy[band] * spectralWeight * (1 - family * .055f)),
                wavelength, MathF.Sqrt(9.80665f * MathF.Tau / wavelength), basis.Steepness * (.79f - band * .095f),
                basis.Phase + (Hash(family, band, 53) * 2 - 1) * MathF.PI + band * .61803398875f));
        }
        Waves = waves.Select(w => w with { Amplitude = w.Amplitude * amplitudeScale, Length = w.Length * lengthScale, Speed = w.Speed / MathF.Sqrt(lengthScale) }).ToArray();
        MaximumHeight = Waves.Sum(w => w.Amplitude);
    }

    public Sample Evaluate(Vector2 position, double seconds)
    {
        float height = 0, velocity = 0; Vector2 slope = Vector2.Zero, displacement = Vector2.Zero;
        foreach (var wave in Waves)
        {
            double phase = wave.Number * Vector2.Dot(wave.Direction, position) - wave.Speed * seconds + wave.Phase;
            float sine = (float)Math.Sin(phase), cosine = (float)Math.Cos(phase);
            height += wave.Amplitude * sine;
            slope += wave.Direction * (wave.Amplitude * wave.Number * cosine);
            displacement += wave.Direction * (wave.Steepness * wave.Amplitude * cosine);
            velocity -= wave.Amplitude * wave.Speed * cosine;
        }
        return new(height, slope, displacement, velocity);
    }

    private static Vector2 Rotate(Vector2 v, float a) => new(v.X * MathF.Cos(a) - v.Y * MathF.Sin(a), v.X * MathF.Sin(a) + v.Y * MathF.Cos(a));
    private static float Lerp(float a, float b, float t) => a + (b - a) * Math.Clamp(t, 0, 1);
    private static float PeakEnergy(float wavelength, float peak)
    {
        float ratio = MathF.Sqrt(peak / wavelength), sigma = ratio <= 1 ? .07f : .09f;
        float peakShape = MathF.Exp(-MathF.Pow(ratio - 1, 2) / (2 * sigma * sigma));
        return Math.Clamp(MathF.Pow(ratio, -5) * MathF.Exp(-1.25f * MathF.Pow(ratio, -4)) * MathF.Pow(3.3f, peakShape) / (MathF.Exp(-1.25f) * 3.3f), 0, 1);
    }
    private static float Hash(int family, int band, int channel)
    {
        unchecked
        {
            uint h = 1588005454u ^ ((uint)(family + 1) * 73244475u) ^ ((uint)(band + 1) * 295559667u) ^ ((uint)(channel + 1) * 668265261u);
            h = (h ^ (h >> 16)) * 2146121005u; h = (h ^ (h >> 15)) * 2221713035u;
            return (float)((h ^ (h >> 16)) / 4294967296.0);
        }
    }
}
