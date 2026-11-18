using Godot;
namespace BoatsNBeasts;

static class VoyageScore
{
    const float Beat = .56f;
    static readonly int[][] Chords =
    [
        [50, 57, 65], [46, 53, 62], [53, 60, 69], [48, 55, 67],
        [43, 50, 58], [46, 53, 65], [45, 52, 61], [50, 57, 65],
        [53, 60, 69], [46, 53, 65], [43, 50, 58], [48, 55, 64],
        [50, 57, 65], [46, 53, 62], [45, 52, 61], [50, 57, 65]
    ];
    static readonly int[] Tune =
    [
        74, 77, 81, 79, 77, 74, 72, 69, 72, 76, 77, 81, 79, 76, 72, 67,
        70, 74, 77, 74, 72, 74, 77, 82, 81, 79, 76, 73, 74, 69, 65, 62,
        81, 84, 86, 84, 82, 81, 77, 74, 79, 82, 81, 77, 76, 79, 84, 79,
        77, 81, 79, 77, 74, 77, 76, 74, 73, 76, 81, 76, 74, 69, 65, 62
    ];

    public static AudioStreamWav[] Build()
    {
        var melody = Tune.Select(Frequency).ToArray();
        var harmony = Chords.Select(chord => chord.Select(Frequency).ToArray()).ToArray();
        var bass = Chords.Select(chord => Frequency(chord[0] - 12)).ToArray();
        float duration = Beat * Tune.Length;
        return
        [
            SeaAudio.Wave(duration, (frame, _) =>
            {
                float time = frame / (float)SeaAudio.Rate;
                int beat = (int)(time / Beat);
                int bar = beat / 4;
                float tick = time - beat * Beat;
                float withinBar = time - bar * 4 * Beat;
                float sound = .21f * Pluck(bass[bar], withinBar, 1.35f)
                    + .12f * Pluck(harmony[bar][beat % 3], tick, 3)
                    + .14f * Pluck(melody[beat], tick, 4.5f);
                if (beat > 0) sound += .035f * Pluck(melody[beat - 1], tick + Beat, 2.4f);
                return sound * Seam(time, duration);
            }, true),
            SeaAudio.Wave(duration, (frame, noise) =>
            {
                float time = frame / (float)SeaAudio.Rate;
                int beat = (int)(time / Beat);
                float tick = time - beat * Beat;
                float thud = (beat % 2 == 0 ? .54f : .26f) * Drum(tick, beat % 4 == 0 ? 79 : 91);
                float brush = .14f * noise * Accent(tick, 43) + .095f * noise * Accent(tick - Beat * .56f, 54);
                float wood = .16f * Pluck(harmony[beat / 4][2], tick - Beat * .56f, 17);
                return (thud + brush + wood) * Seam(time, duration);
            }, true),
            SeaAudio.Wave(duration, (frame, _) =>
            {
                float time = frame / (float)SeaAudio.Rate;
                int beat = (int)(time / Beat);
                int bar = beat / 4;
                float tick = time - beat * Beat;
                float withinBar = time - bar * 4 * Beat;
                float low = .34f * Bow(bass[bar], withinBar, 4 * Beat);
                float fifth = .17f * Bow(harmony[bar][1] * .5f, withinBar, 4 * Beat);
                float pulse = .15f * Pluck(bass[bar] * (beat % 4 == 3 ? 3 : 2), tick, 5.5f);
                return (low + fifth + pulse) * Seam(time, duration);
            }, true)
        ];
    }

    static float Seam(float time, float end) => Math.Clamp(Math.Min(time, end - time) * 25, 0, 1);
    static float Frequency(int note) => 440 * MathF.Pow(2, (note - 69) / 12f);
    static float Accent(float time, float decay) => time < 0 ? 0 : Math.Min(1, time * 145) * MathF.Exp(-time * decay);

    static float Pluck(float frequency, float time, float decay)
    {
        if (time < 0) return 0;
        float phase = Mathf.Tau * frequency * time;
        return (MathF.Sin(phase) + .25f * MathF.Sin(phase * 2.006f) + .09f * MathF.Sin(phase * 3)) * Accent(time, decay);
    }

    static float Drum(float time, float frequency)
    {
        float phase = Mathf.Tau * (frequency * time + 14 * (1 - MathF.Exp(-time * 5)));
        return (MathF.Sin(phase) + .21f * MathF.Sin(2.1f * phase)) * Accent(time, 15);
    }

    static float Bow(float frequency, float time, float span)
    {
        float phase = Mathf.Tau * frequency * time;
        float envelope = Math.Clamp(Math.Min(time * 6, (span - time) * 12), 0, 1);
        float tremolo = .85f + .15f * MathF.Sin(time * Mathf.Tau * 4.4f);
        return (MathF.Sin(phase) + .31f * MathF.Sin(phase * 2) + .17f * MathF.Sin(phase * 3.02f)) * envelope * tremolo;
    }
}
