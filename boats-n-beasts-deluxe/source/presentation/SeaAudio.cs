using Godot;
namespace BoatsNBeasts;

public partial class SeaAudio : Node
{
    const int Rate = 22050;
    readonly Dictionary<string, AudioStreamPlayer> cues = new();
    AudioStreamPlayer sea = null!, music = null!;
    public bool InBattle { get; set; }
    bool muted;

    public bool Muted
    {
        get => muted;
        set
        {
            muted = value;
            if (sea == null) return;
            if (muted)
            {
                sea.Stop();
                music.Stop();
                foreach (var player in cues.Values) player.Stop();
            }
            else { sea.Play(); music.Play(); }
        }
    }

    public override void _Ready()
    {
        sea = new() { Stream = SeaLoop(), VolumeDb = -24 };
        music = new() { Stream = MusicLoop(), VolumeDb = -21 };
        AddChild(sea);
        AddChild(music);

        AddCue("shot", Thump(.12f, 96, .64f));
        AddCue("harpoon", Chime(.18f, [311], .46f));
        AddCue("kill", Thump(.17f, 160, .24f));
        AddCue("hurt", Thump(.26f, 65, .78f));
        AddCue("boostStart", Thump(.23f, 132, .38f));
        AddCue("broadside", Thump(.46f, 66, .93f));
        AddCue("bulwark", Chime(.34f, [110, 165, 220], .56f));
        AddCue("blink", Chime(.42f, [392, 587, 784], .58f));
        AddCue("pufferExplosion", Thump(.38f, 77, .68f));
        AddCue("bossExplosion", Thump(.44f, 58, .8f));
        AddCue("explosion", Thump(.26f, 85, .51f));
        AddCue("chain", Chime(.46f, [440, 587, 660], .58f));
        AddCue("treasure", Chime(.55f, [440, 554, 659], .58f));
        AddCue("heal", Chime(.46f, [330, 495], .42f));
        AddCue("level", Chime(.35f, [370, 494], .45f));
        AddCue("upgrade", Chime(.31f, [494, 659], .48f));
        AddCue("beaconStart", Chime(.4f, [262, 330], .37f));
        AddCue("beacon", Chime(.85f, [294, 440, 587, 740], .68f));
        AddCue("boss", Chime(1.25f, [98, 139, 147], .75f));
        AddCue("enraged", Thump(.54f, 55, .68f));
        AddCue("defeat", Chime(1.1f, [293, 220, 147], .62f));
        AddCue("victory", Chime(1.55f, [392, 494, 587, 784, 988], .72f));
        if (!Muted) { sea.Play(); music.Play(); }
    }

    public override void _Process(double delta)
    {
        music.VolumeDb = Mathf.Lerp(music.VolumeDb, InBattle ? -15 : -21, 1 - Mathf.Exp(-(float)delta * 1.8f));
    }

    public void Play(string cue)
    {
        if (!Muted && cues.TryGetValue(cue, out var player)) player.Play();
    }

    void AddCue(string name, AudioStreamWav wave)
    {
        var player = new AudioStreamPlayer { Stream = wave, MaxPolyphony = 3, VolumeDb = -14 };
        cues.Add(name, player);
        AddChild(player);
    }

    static AudioStreamWav Chime(float duration, float[] tones, float volume) => Wave(duration, (frame, _) =>
    {
        float time = frame / (float)Rate;
        float cue = 0;
        for (int i = 0; i < tones.Length; i++)
        {
            float note = time - i * duration * .13f;
            if (note < 0) break;
            float phase = Mathf.Tau * tones[i] * note;
            float envelope = Math.Min(1, note * 110) * MathF.Exp(-note * 5.6f / duration);
            cue += (Mathf.Sin(phase) + .2f * Mathf.Sin(phase * 2.02f)) * envelope;
        }
        return cue * volume * .48f;
    });

    static AudioStreamWav Thump(float duration, float frequency, float volume)
    {
        float softened = 0;
        return Wave(duration, (frame, noise) =>
        {
            float time = frame / (float)Rate;
            softened += (noise - softened) * .24f;
            float phase = Mathf.Tau * frequency * time * (1 - .42f * time / duration);
            float envelope = Math.Min(1, time * 800) * MathF.Exp(-time * 5.5f / duration);
            return (Mathf.Sin(phase) * .7f + softened * .7f) * envelope * volume;
        });
    }

    static AudioStreamWav SeaLoop()
    {
        const float duration = 12;
        float low = 0, high = 0;
        return Wave(duration, (frame, noise) =>
        {
            float time = frame / (float)Rate;
            float phase = Mathf.Tau * time / duration;
            low += (noise - low) * .022f;
            high += (noise - high) * .16f;
            float swell = .37f + .18f * Mathf.Sin(phase * 3) + .12f * Mathf.Sin(phase * 5);
            float fade = Math.Clamp(Math.Min(time, duration - time) * 2, 0, 1);
            return (low * 2.7f + high * .53f) * swell * fade;
        }, true);
    }

    static AudioStreamWav MusicLoop()
    {
        const float beat = .58f;
        int[][] chords = [[50, 57, 65], [46, 53, 62], [53, 60, 69], [48, 55, 67],
            [43, 50, 58], [46, 53, 65], [45, 52, 61], [50, 57, 65]];
        int[] tune = [74, 77, 81, 79, 77, 74, 72, 69, 72, 76, 77, 81, 79, 76, 72, 67,
            70, 74, 77, 74, 72, 74, 77, 82, 81, 79, 76, 73, 74, 69, 65, 62];
        var bass = chords.Select(chord => Frequency(chord[0] - 12)).ToArray();
        var harmony = chords.Select(chord => chord.Select(Frequency).ToArray()).ToArray();
        var melody = tune.Select(Frequency).ToArray();
        const float duration = 32 * beat;
        return Wave(duration, (frame, _) =>
        {
            float time = frame / (float)Rate;
            int note = Math.Min(31, (int)(time / beat));
            int bar = note / 4;
            float barTime = time - bar * 4 * beat;
            float noteTime = time - note * beat;
            float sound = .22f * Pluck(bass[bar], barTime, 1.35f);
            sound += .14f * Pluck(harmony[bar][note % 3], noteTime, 3);
            sound += .12f * Pluck(melody[note], noteTime, 4.6f);
            if (note > 0)
                sound += .038f * Pluck(melody[note - 1], noteTime + beat, 2.4f);
            return sound * Math.Clamp(Math.Min(time, duration - time) * 4, 0, 1);
        }, true);
    }

    static float Frequency(int note) => 440 * MathF.Pow(2, (note - 69) / 12f);

    static float Pluck(float frequency, float time, float decay)
    {
        float phase = Mathf.Tau * frequency * time;
        float envelope = Math.Min(1, time * 95) * MathF.Exp(-time * decay);
        return (Mathf.Sin(phase) + .25f * Mathf.Sin(phase * 2.006f) + .09f * Mathf.Sin(phase * 3)) * envelope;
    }

    static AudioStreamWav Wave(float duration, Func<int, float, float> sample, bool loop = false)
    {
        int frames = (int)(duration * Rate);
        var data = new byte[frames * 2];
        var noise = new Random(47293);
        for (int i = 0; i < frames; i++)
        {
            short value = (short)(Math.Clamp(sample(i, 2 * noise.NextSingle() - 1), -1, 1) * short.MaxValue);
            data[2 * i] = (byte)value;
            data[2 * i + 1] = (byte)(value >> 8);
        }
        return new AudioStreamWav
        {
            Format = AudioStreamWav.FormatEnum.Format16Bits, MixRate = Rate, Data = data,
            LoopMode = loop ? AudioStreamWav.LoopModeEnum.Forward : AudioStreamWav.LoopModeEnum.Disabled,
            LoopEnd = frames
        };
    }
}
